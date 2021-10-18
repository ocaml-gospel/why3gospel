(**************************************************************************)
(*                                                                        *)
(*  GOSPEL -- A Specification Language for OCaml                          *)
(*                                                                        *)
(*  Copyright (c) 2018- The VOCaL Project                                 *)
(*                                                                        *)
(*  This software is free software, distributed under the MIT license     *)
(*  (as described in file LICENSE enclosed).                              *)
(**************************************************************************)

open Gospel.Ttypes
open Gospel.Tterm
open Gospel.Tmodule
module Hid = Hashtbl.Make (Gospel.Identifier.Ident)
module Mstr = Gospel.Tmodule.Mstr

let driver = Hid.create 0
let add_ls prefix s ls = Hid.add driver ls.ls_name (s :: prefix)
let add_ts prefix s ts = Hid.add driver ts.ts_ident (s :: prefix)

let init ns =
  let rec visit prefix ns =
    Mstr.iter (add_ls prefix) ns.ns_ls;
    Mstr.iter (add_ts prefix) ns.ns_ts;
    Mstr.iter
      (fun p ns ->
        let prefix = if p = "Gospelstdlib" then prefix else p :: prefix in
        visit prefix ns)
      ns.ns_ns
  in
  visit [] ns;
  let ts_int = ns_find_ts ns [ "Gospelstdlib"; "int" ] in
  Hid.replace driver ts_int.ts_ident [ "int63" ]

let query_syntax str = Hid.find_opt driver str
