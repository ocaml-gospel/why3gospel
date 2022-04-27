(**************************************************************************)
(*                                                                        *)
(*  GOSPEL -- A Specification Language for OCaml                          *)
(*                                                                        *)
(*  Copyright (c) 2018- The VOCaL Project                                 *)
(*                                                                        *)
(*  This software is free software, distributed under the MIT license     *)
(*  (as described in file LICENSE enclosed).                              *)
(**************************************************************************)

module P = Ppxlib
open Trans
open Why3
open Ptree
module Mstr = Why3.Wstdlib.Mstr

let print_modules = Debug.lookup_flag "print_modules"

let mk_id ?(loc = Loc.dummy_position) name =
  { id_str = name; id_ats = []; id_loc = loc }

let use ?(import = false) q =
  let id = match q with Qident id | Qdot (_, id) -> id in
  let loc = id.id_loc in
  Typing.open_scope loc id;
  let use_import = Duseimport (loc, import, [ (q, None) ]) in
  Typing.add_decl loc use_import;
  Typing.close_scope loc ~import

let extra_use s = use ~import:true (Qdot (Qident (mk_id "gospel"), mk_id s))

let read_file file nm c =
  let lb = Lexing.from_channel c in
  P.Location.init lb file;
  let ocaml_sig = Gospel.Parser_frontend.parse_ocaml_signature_lb lb in
  Gospel.Parser_frontend.(parse_signature_gospel ~filename:file ocaml_sig nm)

let type_check name nm sigs =
  (* Include current file directory during type-checking.
     This is closer to how [gospel check] actually works. *)
  let md = Gospel.Tmodule.init_muc name in
  let load_path = [ Filename.dirname name ] in
  let penv = Gospel.Typing.penv load_path (Gospel.Utils.Sstr.singleton nm) in
  let md = List.fold_left (Gospel.Typing.type_sig_item penv) md sigs in
  assert (List.length md.muc_import = 1);
  let ns = List.hd md.muc_import in
  (ns, Gospel.Tmodule.wrap_up_muc md)

module Ut = Gospel.Uast

(* extract additional uses and vals from file.mli.why3, if any *)
let extract_use sig_item =
  match sig_item.Ut.sdesc with
  | Sig_ghost_open { popen_expr = { txt = Lident s } } when s = "Gospelstdlib"
    ->
      None
  | Sig_ghost_open { popen_expr = { txt = Lident s } } -> Some s
  | _ -> None

let extract_vals m sig_item =
  match sig_item.Ut.sdesc with
  | Sig_val { vname; vtype } -> Mstr.add vname.txt vtype m
  | _ -> m

let include_extra_vals extra_vals sig_item =
  match sig_item.Ut.sdesc with
  | Sig_val ({ vname } as sval) -> (
      try
        let vtype = Mstr.find vname.txt extra_vals in
        { sig_item with sdesc = Sig_val { sval with vtype } }
      with Not_found -> sig_item)
  | _ -> sig_item

let read_extra_file file =
  let why3_file = file ^ ".why3" in
  if Sys.file_exists why3_file then (
    let c = open_in why3_file in
    let nm =
      let f = Filename.basename file in
      String.capitalize_ascii (Filename.chop_extension f)
    in
    let f = read_file why3_file nm c in
    close_in c;
    (Lists.map_filter extract_use f, List.fold_left extract_vals Mstr.empty f))
  else ([], Mstr.empty)

(* TODO equivalent clauses
   let print_equiv file dl =
     let f_equiv = let file = file ^ ".equiv" in
       if Sys.file_exists file then begin
         let backup = file ^ ".bak" in Sys.rename file backup end;
       open_out file in
     let fmt_equiv = formatter_of_out_channel f_equiv in
     let print_args fmt = function
       | Lnone id -> fprintf fmt "%s" id.id_str
       | Lquestion id -> fprintf fmt "?%s" id.id_str
       | Lnamed id -> fprintf fmt "~%s" id.id_str
       | Lghost _ -> assert false in
     let print_decl fmt = function
       | Ddecl _ | Duse _ | Dmodule _ -> () (* FIXME: equiv inside sub-module? *)
       | Dequivalent (fid, argsl, body) ->
         fprintf fmt "let %s @[%a@]@ =@;<1 2>%s@\n@\n"
           fid.id_str (Pp.print_list Pp.space print_args) argsl body in
     List.iter (fun x -> print_decl fmt_equiv x) dl;
     fprintf fmt_equiv "@.";
     close_out f_equiv

   let filter_equiv =
     let mk_equiv acc = function Dequivalent _ as e -> e::acc | _ -> acc in
     List.fold_left mk_equiv []
*)

let read_channel env path file c =
  let open Typing in
  let extra_uses, extra_vals = read_extra_file file in
  let nm =
    let f = Filename.basename file in
    String.capitalize_ascii (Filename.chop_extension f)
  in
  let f = read_file file nm c in
  let f = List.map (include_extra_vals extra_vals) f in
  let ns, f = type_check file nm f in
  Gdriver.init ns;
  let sigs = signature Info.empty_info f.fl_sigs in
  open_file env path;
  let id = mk_id nm in
  open_module id;
  List.iter extra_use extra_uses;
  let rec add_decl = function
    | Gdecl d -> Typing.add_decl Loc.dummy_position d
    | Gmodule (loc, id, dl) ->
        Typing.open_scope id.id_loc id;
        List.iter add_decl dl;
        Typing.close_scope ~import:true loc
  in
  let f = List.flatten sigs in
  List.iter add_decl f;
  close_module Loc.dummy_position;
  let mm = close_file () in
  (* TODO *)
  (* let f = filter_equiv f in
   * if f <> [] then print_equiv file f; *)
  (if Debug.test_flag print_modules then
   let open Why3.Ident in
   let open Why3.Pmodule in
   let print_m _ m = Format.eprintf "%a@\n@." print_module m in
   let add_m _ m mm = Mid.add m.mod_theory.Theory.th_name m mm in
   Mid.iter print_m (Mstr.fold add_m mm Mid.empty));
  mm

let () =
  Env.register_format Why3.Pmodule.mlw_language "gospel" [ "mli" ] read_channel
    ~desc:"GOSPEL format"
