(**************************************************************************)
(*                                                                        *)
(*  GOSPEL -- A Specification Language for OCaml                          *)
(*                                                                        *)
(*  Copyright (c) 2018- The VOCaL Project                                 *)
(*                                                                        *)
(*  This software is free software, distributed under the MIT license     *)
(*  (as described in file LICENSE enclosed).                              *)
(**************************************************************************)

module T = Gospel.Tast
module Th = Gospel.Tast_helper
open Ppxlib
open Gdriver
open Why3
open Ptree

type gdecl = Gdecl of decl | Gmodule of Loc.position * ident * gdecl list

let location { loc_start = b; loc_end = e } = Loc.extract (b, e)
let dummy_loc = Loc.dummy_position

let mk_id ?(id_ats = []) ?(id_loc = Loc.dummy_position) id_str =
  let id_str =
    match id_str with
    | "mixfix [_]" -> "mixfix []"
    (* FIXME: many other cases; see src/core/ident.ml in Why3 sources *)
    | _ -> id_str
  in
  { id_str; id_ats; id_loc }

let mk_qualid_path path id_loc ident =
  match path with
  | [] -> Qident ident
  | q :: r ->
      let mk_qdot q id_str = Qdot (q, mk_id ~id_loc id_str) in
      let id_q = mk_id ~id_loc q in
      let qdot = List.fold_left mk_qdot (Qident id_q) r in
      Qdot (qdot, ident)

let mk_path id_loc = function
  | id :: path -> mk_qualid_path (List.rev path) id_loc (mk_id ~id_loc id)
  | [] -> assert false

let query_path id_loc id =
  let p = match query_syntax id with None -> [ id.id_str ] | Some s -> s in
  mk_path id_loc p

let mk_field ~mut:f_mutable ~ghost:f_ghost f_loc f_ident f_pty =
  { f_loc; f_ident; f_pty; f_mutable; f_ghost }

open Info

module Term = struct
  module Tt = Gospel.Tterm
  module Ts = Gospel.Symbols
  module Ty = Gospel.Ttypes
  module I = Gospel.Identifier.Ident

  let mk_term term_desc term_loc = { term_desc; term_loc }
  let mk_pattern pat_desc pat_loc = { pat_desc; pat_loc }

  let ident_of_vsymbol Ts.{ vs_name = name } =
    mk_id name.I.id_str ~id_loc:(location name.I.id_loc)

  let ident_of_tvsymbol Ty.{ tv_name = name } =
    mk_id name.I.id_str ~id_loc:(location name.I.id_loc)

  let ident_of_lsymbol Ts.{ ls_name = name } =
    mk_id name.I.id_str ~id_loc:(location name.I.id_loc)

  let quant = function
    | Tt.Tforall -> Dterm.DTforall
    | Tt.Texists -> Dterm.DTexists
    | Tt.Tlambda -> Dterm.DTlambda

  let rec pattern pat =
    let loc =
      match pat.Tt.p_loc with None -> dummy_loc | Some l -> location l
    in
    let mk_pattern pat_desc = mk_pattern pat_desc loc in
    let p_node = function
      | Tt.Pwild -> Pwild
      | Tt.Pvar vs -> Pvar (ident_of_vsymbol vs)
      | Tt.Por (p1, p2) -> Por (pattern p1, pattern p2)
      | Tt.Pas (p, vs) -> Pas (pattern p, ident_of_vsymbol vs, false)
      | Tt.Papp (ls, pat_list) when Ts.is_fs_tuple ls ->
          Ptuple (List.map pattern pat_list)
      | Tt.Papp (ls, pat_list) ->
          let id_loc = location ls.ls_name.id_loc in
          let q = query_path id_loc ls.ls_name in
          Papp (q, List.map pattern pat_list)
    in
    mk_pattern (p_node pat.Tt.p_node)

  let rec ty info Ty.{ ty_node } =
    match ty_node with
    | Ty.Tyvar { tv_name } ->
        PTtyvar (mk_id tv_name.id_str ~id_loc:(location tv_name.id_loc))
    | Ty.Tyapp (ts, tyl) when Ty.is_ts_tuple ts ->
        PTtuple (List.map (ty info) tyl)
    | Ty.Tyapp (ts, tyl) when Ty.is_ts_arrow ts ->
        let rec arrow_of_pty_list = function
          | [] -> assert false
          | [ pty ] -> pty
          | arg :: ptyl -> PTarrow (arg, arrow_of_pty_list ptyl)
        in
        arrow_of_pty_list (List.map (ty info) tyl)
    | Ty.Tyapp (({ ts_ident } as tys), tyl) -> (
        let ty_arg = List.map (ty info) tyl in
        let id_loc = location ts_ident.id_loc in
        try
          let info_path = find_ts info tys in
          let curr_path = info.info_path in
          let path = reduce_path (List.rev info_path) (List.rev curr_path) in
          let id = mk_id ~id_loc ts_ident.id_str in
          let qualid = mk_qualid_path path id_loc id in
          PTtyapp (qualid, ty_arg)
        with Not_found ->
          let q = query_path id_loc ts_ident in
          PTtyapp (q, ty_arg))

  let binder_of_vsymbol info vs =
    let loc = vs.Ts.vs_name.I.id_loc in
    let id = ident_of_vsymbol vs in
    let pty = ty info vs.vs_ty in
    (location loc, Some id, false, Some pty)

  let param_of_vsymbol info Ts.{ vs_name; vs_ty } =
    let id_loc = location vs_name.I.id_loc in
    let id = mk_id vs_name.I.id_str ~id_loc in
    let pty = ty info vs_ty in
    (id_loc, Some id, false, pty)

  let binop = function
    | Tt.Tand -> Dterm.DTand
    | Tt.Tand_asym -> Dterm.DTand_asym
    | Tt.Tor -> Dterm.DTor
    | Tt.Tor_asym -> Dterm.DTor_asym
    | Tt.Timplies -> Dterm.DTimplies
    | Tt.Tiff -> Dterm.DTiff

  let rec term info t =
    let id_loc = location t.Tt.t_loc in
    let mk_term term_desc = mk_term term_desc id_loc in
    let t_node = function
      | Tt.Ttrue -> Ttrue
      | Tt.Tfalse -> Tfalse
      | Tt.Tvar vs -> Tident (Qident (ident_of_vsymbol vs))
      | Tt.Tnot t -> Tnot (term info t)
      | Tt.Told t -> Tat (term info t, mk_id Dexpr.old_label ~id_loc)
      | Tt.Tconst c -> (
          match c with
          | Pconst_integer (s, None) ->
              (* FIXME: check that [neg] parameter *)
              let n = Number.(int_literal ILitDec ~neg:false s) in
              Tconst (Constant.ConstInt n)
          | _ -> assert false (* TODO *))
      | Tt.Tif (t1, t2, t3) -> Tif (term info t1, term info t2, term info t3)
      | Tt.Tlet (vs, t1, t2) ->
          Tlet (ident_of_vsymbol vs, term info t1, term info t2)
      | Tt.Tcase (t, pat_term_list) ->
          let f_pair (pat, t) = (pattern pat, term info t) in
          Tcase (term info t, List.map f_pair pat_term_list)
      | Tt.Tquant (q, vs_list, t) ->
          let binder_list = List.map (binder_of_vsymbol info) vs_list in
          Tquant (quant q, binder_list, [], term info t)
      | Tt.Tbinop (op, t1, t2) -> Tbinop (term info t1, binop op, term info t2)
      | Tt.Tfield (t, f) ->
          let id_loc = location f.ls_name.I.id_loc in
          let q = query_path id_loc f.ls_name in
          Tidapp (q, [ term info t ])
      | Tt.Tapp (ls, []) ->
          let id_loc = location ls.ls_name.I.id_loc in
          let q = query_path id_loc ls.ls_name in
          Tident q
      | Tt.Tapp (ls, term_list) when Ts.ls_equal ls Ts.fs_apply -> (
          match term_list with
          | [ fs; arg ] -> Tapply (term info fs, term info arg)
          | _ -> assert false)
      | Tt.Tapp ({ ls_name }, term_list) ->
          let id_loc = location ls_name.I.id_loc in
          let term_list = List.map (term info) term_list in
          let p =
            match query_syntax ls_name with
            | None -> [ ls_name.id_str ]
            | Some s -> s
          in
          let q = mk_path id_loc p in
          Tidapp (q, term_list)
    in
    mk_term (t_node t.Tt.t_node)
end

let td_params (tvs, _) = Term.ident_of_tvsymbol tvs

(** Visibility of type declarations. An alias type cannot be private, so we
    check whether or not the GOSPEL type manifest is [None]. *)
let td_vis_from_manifest = function None -> Private | Some _ -> Public

(** Convert a GOSPEL type definition into a Why3's Ptree [type_def]. If the
    GOSPEL type manifest is [None], then the type is defined via its
    specification fields. Otherwise, it is an alias type. *)
let td_def info td_fields td_manifest =
  let field_of_lsymbol (ls, mut) =
    let id = Term.ident_of_lsymbol ls in
    let pty = Term.ty info Term.(Opt.get ls.Ts.ls_value) in
    mk_field id.id_loc id pty ~mut ~ghost:true
  in
  let td_def_of_ty_fields ty_fields =
    TDrecord (List.map field_of_lsymbol ty_fields)
  in
  match td_manifest with
  | None -> td_def_of_ty_fields td_fields
  | Some ty -> TDalias (Term.ty info ty)

let type_decl info (T.{ td_ts = { ts_ident }; td_spec; td_manifest } as td) =
  let td_mut, td_fields, td_inv =
    match td_spec with
    | None -> (false, [], [])
    | Some td ->
        ( td.ty_ephemeral,
          td.T.ty_fields,
          List.map (Term.term info) td.ty_invariants )
  in
  {
    td_loc = location td.td_loc;
    td_ident = mk_id ts_ident.id_str ~id_loc:(location td.td_loc);
    td_params = List.map td_params td.td_params;
    td_vis = td_vis_from_manifest td_manifest;
    td_mut;
    td_inv;
    td_wit = [];
    td_def = td_def info td_fields td_manifest;
  }

let type_decl info (T.{ td_ts } as td) =
  add_ts info td_ts;
  type_decl info td

let mk_expr expr_desc expr_loc = { expr_desc; expr_loc }

let mk_logic_decl ld_loc ld_ident ld_params ld_type ld_def =
  { ld_loc; ld_ident; ld_params; ld_type; ld_def }

let mk_ret_type = function [ ty ] -> ty | l -> PTtuple l
let loc_of_vs vs = Term.(location vs.Ts.vs_name.I.id_loc)

let ident_of_lb_arg = function
  | T.Lunit -> mk_id "()"
  | lb -> Term.ident_of_vsymbol (Th.vs_of_lb_arg lb)

let loc_of_lb_arg = function
  | T.Lunit -> dummy_loc
  | lb -> loc_of_vs (Th.vs_of_lb_arg lb)

(** Given the result type [sp_ret] of a function and a GOSPEL postcondition
    [post] (represented as a [term]), convert it into a Why3's Ptree
    postcondition of the form [Loc.position * (pattern * term)]. *)
let sp_post info sp_ret post =
  let mk_post post =
    let pvar_of_lb_arg_list lb_arg_list =
      let mk_pvar lb =
        (* create a [Pvar] pattern out of a [Tt.lb_arg] *)
        let pat =
          match lb with T.Lunit -> Pwild | _ -> Pvar (ident_of_lb_arg lb)
        in
        Term.mk_pattern pat dummy_loc
      in
      List.map mk_pvar lb_arg_list
    in
    let pat =
      match pvar_of_lb_arg_list sp_ret with
      | [ p ] -> p
      | pl -> Term.mk_pattern (Ptuple pl) dummy_loc
    in
    (dummy_loc, [ (pat, Term.term info post) ])
  in
  List.map mk_post post

open Term

(** Convert a GOSPEL exception postcondition of the form
    [(pattern * post) list Mxs.t] into a Why3's Ptree [xpost] of the form
    [Loc.position * (qualid * (pattern * term) option) list]. *)
let sp_xpost info xpost =
  let mk_xpost_list (xs, pat_post_list) =
    let id_loc = location xs.Ty.xs_ident.I.id_loc in
    let mk_xpost (pat, post) =
      let q = Qident (mk_id xs.Ty.xs_ident.I.id_str ~id_loc) in
      let post = term info post in
      (q, Some (Term.pattern pat, post))
    in
    (id_loc, List.map mk_xpost pat_post_list)
  in
  List.map mk_xpost_list xpost

let sp_writes info = List.map (term info)

let rec term_or_of_term_list = function
  | [] -> assert false
  | [ t ] -> t
  | t :: r ->
      let term_or = Tbinop (t, Dterm.DTor, term_or_of_term_list r) in
      mk_term term_or t.term_loc

(** Convert a Why3's precondition into a Why3's Ptree [xpost]. *)
let xpost_of_checks pre =
  let id_loc = pre.term_loc in
  let qid = Qident (mk_id "Invalid_argument" ~id_loc) in
  let pat = mk_pattern Pwild id_loc in
  let txs = mk_term (Tnot pre) id_loc in
  (id_loc, [ (qid, Some (pat, txs)) ])

let spec_with_checks info val_spec pre checks =
  let xpost_checks = xpost_of_checks (term_or_of_term_list checks) in
  {
    sp_pre = List.map (term info) pre;
    sp_post = sp_post info val_spec.T.sp_ret val_spec.sp_post;
    sp_xpost = xpost_checks :: sp_xpost info val_spec.sp_xpost;
    sp_reads = [];
    sp_writes = sp_writes info val_spec.sp_wr;
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

let spec info val_spec =
  {
    sp_pre =
      List.map (fun t -> term info t) (val_spec.T.sp_pre @ val_spec.T.sp_checks);
    sp_post = sp_post info val_spec.sp_ret val_spec.sp_post;
    sp_xpost = sp_xpost info val_spec.sp_xpost;
    sp_reads = [];
    sp_writes = sp_writes info val_spec.sp_wr;
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

let empty_spec =
  {
    sp_pre = [];
    sp_post = [];
    sp_xpost = [];
    sp_reads = [];
    sp_writes = [];
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

(** Convert GOSPEL [val] declarations into Why3's Ptree [val] declarations. *)
let val_decl info vd g =
  let mk_single_param lb_arg =
    let add_at_id at id = { id with id_ats = ATstr at :: id.id_ats } in
    let id_loc = loc_of_lb_arg lb_arg in
    let pty = ty info (Th.ty_of_lb_arg lb_arg) in
    let id = ident_of_lb_arg lb_arg in
    let id, ghost, pty =
      match lb_arg with
      | Lunit -> (id, false, pty)
      | Lnone _ -> (id, false, pty)
      | Lghost _ -> (id, true, pty)
      | Lnamed _ -> (add_at_id Ocaml.Print.named_arg id, false, pty)
      | Loptional _ ->
          let id = add_at_id Ocaml.Print.optional_arg id in
          (id, false, PTtyapp (Qident (mk_id "option" ~id_loc), [ pty ]))
    in
    (id_loc, Some id, ghost, pty)
  in
  let mk_ghost_param = function
    | T.Lunit | T.Lnone _ | Lnamed _ | Loptional _ -> assert false
    | T.Lghost vs ->
        let id_loc = location vs.Ts.vs_name.I.id_loc in
        let id = Some (mk_id vs.Ts.vs_name.I.id_str ~id_loc) in
        let pty = Term.ty info vs.vs_ty in
        (id_loc, id, true, pty)
  in
  let rec mk_param lb_args =
    match lb_args with
    | [] -> []
    | (T.Lghost _ as lb) :: lb_args -> mk_ghost_param lb :: mk_param lb_args
    | lb :: lb_args -> mk_single_param lb :: mk_param lb_args
  in
  let mk_vals params ret pat mask =
    let vd_str = vd.T.vd_name.I.id_str in
    let mk_id id_str = mk_id id_str ~id_loc:(location vd.T.vd_loc) in
    let mk_val id params ret pat mask spec =
      let e_any = Eany (params, Expr.RKnone, ret, pat, mask, spec) in
      let e_any = mk_expr e_any (location vd.T.vd_loc) in
      Dlet (id, g, Expr.RKnone, e_any)
    in
    match vd.T.vd_spec with
    | None -> [ mk_val (mk_id vd_str) params ret pat mask empty_spec ]
    | Some s ->
        let unsafe_spec = spec info s in
        if s.sp_checks = [] then
          [ mk_val (mk_id vd_str) params ret pat mask unsafe_spec ]
        else
          let id_unsafe = mk_id ("unsafe_" ^ vd_str) in
          let checks_term = List.map (term info) s.sp_checks in
          let spec_checks = spec_with_checks info s s.sp_pre checks_term in
          [
            mk_val id_unsafe params ret pat mask unsafe_spec;
            mk_val (mk_id vd_str) params ret pat mask spec_checks;
          ]
  in
  let params, ret, pat, mask =
    let params, pat, mask =
      let params = mk_param vd.T.vd_args in
      let mk_pat lb =
        let loc = loc_of_lb_arg lb in
        Term.mk_pattern (Pvar (ident_of_lb_arg lb)) loc
      in
      let mk_mask = function
        | T.Lunit | T.Lnone _ | T.Loptional _ | T.Lnamed _ -> Ity.MaskVisible
        | T.Lghost _ -> Ity.MaskGhost
      in
      let lb_list = vd.T.vd_ret in
      let pat_list = List.map mk_pat lb_list in
      let mask_list = List.map mk_mask lb_list in
      let pat, mask =
        match (pat_list, mask_list) with
        | [], [] ->
            (* in this case, the return is of type unit *)
            (Term.mk_pattern Pwild dummy_loc, Ity.MaskVisible)
        | [ p ], [ m ] -> (p, m)
        | pl, ml ->
            assert (List.length pl = List.length ml);
            let loc = location vd.T.vd_loc in
            (* TODO: better location? *)
            (Term.mk_pattern (Ptuple pl) loc, Ity.MaskTuple ml)
      in
      (params, pat, mask)
    in
    let ret =
      List.map Th.ty_of_lb_arg vd.T.vd_ret |> List.map (ty info) |> fun ret ->
      mk_ret_type ret |> Option.some
    in
    (params, ret, pat, mask)
  in
  mk_vals params ret pat mask

(** Convert GOSPEL logical declaration (function or predicate) into Why3's Ptree
    logical declaration. *)
let function_ info (T.{ fun_ls = { ls_name; ls_value } } as f) =
  add_ls info f.fun_ls;
  let loc = location f.T.fun_loc in
  let id_loc = location ls_name.I.id_loc in
  let id = mk_id ls_name.I.id_str ~id_loc in
  let params = List.map (param_of_vsymbol info) f.fun_params in
  let pty = Opt.map (ty info) ls_value in
  let term = Opt.map (term info) f.T.fun_def in
  Dlogic [ mk_logic_decl loc id params pty term ]

(** Convert GOSPEL axioms into Why3's Ptree axioms. *)
let axiom info T.{ ax_name; ax_term } =
  let id_loc = location ax_name.I.id_loc in
  let id = mk_id ax_name.I.id_str ~id_loc in
  let term = (term info) ax_term in
  Dprop (Decl.Paxiom, id, term)

(** Convert GOSPEL exceptions into Why3's Ptree exceptions. *)
let exn info T.{ exn_constructor = { ext_ident; ext_xs }; exn_loc } =
  add_xs info ext_xs;
  let id = mk_id ext_ident.id_str ~id_loc:(location ext_ident.id_loc) in
  match ext_xs.Ty.xs_type with
  | Exn_tuple [ { ty_node = Ty.Tyapp (ts, tyl) } ] when Ty.is_ts_tuple ts ->
      Dexn (id, PTtuple (List.map (ty info) tyl), Ity.MaskVisible)
  | Exn_tuple tyl -> Dexn (id, PTtuple (List.map (ty info) tyl), Ity.MaskVisible)
  | Exn_record _ ->
      let loc = location exn_loc in
      Loc.errorm ~loc "Exceptions with record arguments is not supported."

let sig_open file mm loc =
  let dot_name = Qdot (Qident (mk_id file), mk_id mm) in
  Duseimport (loc, false, [ (dot_name, None) ])

let signature =
  let mod_type_table : (string, gdecl list) Hashtbl.t = Hashtbl.create 16 in

  (* Convert a GOSPEL module declaration into a Why3 scope. *)
  let rec module_declaration info T.{ md_name; md_type; md_loc } =
    let loc = location md_loc in
    let id = mk_id md_name.I.id_str ~id_loc:(location md_name.I.id_loc) in
    let info = update_path info md_name.I.id_str in
    Gmodule (loc, id, module_type info md_type)
  and module_type info mt =
    match mt.T.mt_desc with
    | T.Mod_ident s -> (
        match s with
        | [ s ] ->
            (* retrieve the list of declarations corresponding
               to module type [s] *)
            Hashtbl.find mod_type_table s
            (* TODO: catch Not_found *)
        | _ -> assert false)
    | T.Mod_signature s -> List.flatten (signature info s)
    | T.Mod_functor (arg_name, arg, body) ->
        let id_loc = location arg_name.I.id_loc in
        let id_str = arg_name.I.id_str in
        let id = mk_id id_str ~id_loc in
        let info_arg = update_path info id_str in
        (* we treat the functor argument before the body in order to correctly
           update the info table *)
        let mod_arg = module_type info_arg (Opt.get arg) in
        let body = module_type info body in
        Gmodule (id_loc, id, mod_arg) :: body
    | T.Mod_with _ (* of module_type * with_constraint list *) ->
        assert false (* TODO *)
    | T.Mod_typeof _ (* of Oparsetree.module_expr *) -> assert false (* TODO *)
    | T.Mod_extension _ (* of Oparsetree.extension *) -> assert false (* TODO *)
    | T.Mod_alias _ (* of string list *) -> assert false
  (* TODO *)
  and module_type_declaration info mtd =
    let decls =
      match mtd.T.mtd_type with
      | None -> []
      | Some mt ->
          let mtd_name = mtd.T.mtd_name.id_str in
          let info = update_path info mtd_name in
          module_type info mt
    in
    Hashtbl.add mod_type_table mtd.mtd_name.I.id_str decls
  and signature_item info i =
    match i.T.sig_desc with
    | T.Sig_val (vd, g) -> List.map (fun d -> Gdecl d) (val_decl info vd g)
    | T.Sig_type (_rec_flag, tdl, _gh) ->
        [ Gdecl (Dtype (List.map (type_decl info) tdl)) ]
    | T.Sig_typext _ (*  of Oparsetree.type_extension *) ->
        assert false (*TODO*)
    | T.Sig_module md -> [ module_declaration info md ]
    | T.Sig_recmodule _ (* of module_declaration list *) ->
        assert false (*TODO*)
    | T.Sig_modtype mtd ->
        module_type_declaration info mtd;
        []
    | T.Sig_exception exn_cstr -> [ Gdecl (exn info exn_cstr) ]
    | T.Sig_open (_, false) -> []
    | T.Sig_open ({ opn_id = [ "Gospelstdlib" ]; opn_loc }, true) ->
        (* The GOSPEL standard library is opened by default. We map it into a
           custom Why3 file. *)
        [ Gdecl (sig_open "gospel" "Gospelstdlib" (location opn_loc)) ]
    | T.Sig_open ({ opn_id; opn_loc }, true) ->
        let loc = location opn_loc in
        List.map (fun mm -> Gdecl (sig_open "gospel" mm loc)) opn_id
    | T.Sig_include _ (* of Oparsetree.include_description *) ->
        assert false (*TODO*)
    | T.Sig_class _ (* of Oparsetree.class_description list *) ->
        assert false (*TODO*)
    | T.Sig_class_type _ (* of Oparsetree.class_type_declaration list *) ->
        assert false (*TODO*)
    | T.Sig_attribute _ -> []
    | T.Sig_extension _ (* of Oparsetree.extension * Oparsetree.attributes *) ->
        assert false (*TODO*)
    | T.Sig_use s ->
        let loc = location i.T.sig_loc in
        let s = String.uncapitalize_ascii s
        and nm = String.capitalize_ascii s in
        [ Gdecl (sig_open s nm loc) ]
    | T.Sig_function f -> [ Gdecl (function_ info f) ]
    | T.Sig_axiom ax -> [ Gdecl (axiom info ax) ]
  (*TODO*)
  and signature info s = List.map (signature_item info) s in
  signature
