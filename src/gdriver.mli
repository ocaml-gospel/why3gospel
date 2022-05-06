(**************************************************************************)
(*                                                                        *)
(*  GOSPEL -- A Specification Language for OCaml                          *)
(*                                                                        *)
(*  Copyright (c) 2018- The VOCaL Project                                 *)
(*                                                                        *)
(*  This software is free software, distributed under the MIT license     *)
(*  (as described in file LICENSE enclosed).                              *)
(**************************************************************************)

open Gospel.Identifier

val init : Gospel.Tmodule.namespace -> unit

val query_syntax : Ident.t -> string list option
(** [query_syntax s] is the WhyML counterpart of the GOSPEL expression [s], if
    any.*)
