val f1 : 'a list -> unit
(*@ f1 l [l': 'a List.t] *)

val f2 : 'a list -> int
(*@ r = f2 l
      ensures r = List.length l *)

val f3 : 'a list -> 'a * 'a list
(*@ a, r = f3 l
      requires List.length l > 0
      ensures  a = List.hd l && r = List.tl l *)

val f4 : 'a list -> int -> 'a option
(*@ r = f4 l i
      ensures r = List.nth_opt l i
      ensures match r with
              | Some v -> v = List.nth l i && v = l[i]
              | _ -> false *)

val f5 : 'a list -> 'a list
(*@ r = f5 l
      ensures r = List.rev l *)

val f6 : 'a -> int -> 'a list
(*@ r = f6 x n
      ensures r = List.init n (fun _i -> x) *)

val f7 : 'a list -> 'a list
(*@ r = f7 l
      ensures r = List.map (fun x -> x) l
      ensures r = List.mapi (fun _i x -> x) l *)

val f8 : 'a list -> 'b -> 'b
(*@ r = f8 l acc
      ensures r = List.fold_left (fun a _x -> a) acc l
      ensures r = List.fold_right (fun _x a -> a) l acc *)

val f9 : 'a list -> 'b list -> 'a list
(*@ r = f9 l1 l2
      ensures r = List.map2 (fun x _y -> x) l1 l2 *)

val f10 : 'a list -> 'a -> bool
(*@ b = f10 l x
      ensures b <-> List.for_all (fun y -> x = y) l
      ensures b <-> List._exists (fun y -> x = y) l *)

val f11 : 'a list -> 'a list -> bool
(*@ b = f11 l1 l2
      ensures b <-> List.for_all2 (fun x y -> x = y) l1 l2
      ensures b <-> List._exists2 (fun x y -> x = y) l1 l2 *)

val f12 : 'a list -> 'a -> bool
(*@ b = f12 l x
      ensures b <-> List.mem x l *)

val f13 : 'a list -> unit
(*@ f13 l
      ensures List.(of_seq (to_seq l)) = l *)
