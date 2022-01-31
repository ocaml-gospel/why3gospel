type 'a t
(*@ model view : 'a bag *)

(*@ function to_bag (t: 'a t) : 'a bag = t.view *)
(*@ coercion *)

val f1 : int -> 'a -> 'a t -> int
(*@ r = f1 a x t
      requires a = 0
      requires Bag.occurrences x t = 42
      requires Bag.cardinal t = 42
      ensures r = Bag.occurrences x t *)

val f2 : 'a t -> bool
(*@ b = f2 t
      ensures b <-> Bag.is_empty t
      ensures b <-> t = Bag.empty *)

val f3 : 'a -> 'a t -> bool
(*@ b = f3 x t
      ensures b <-> Bag.mem x t *)

val f4 : 'a -> 'a t -> 'a t
(*@ r = f4 x t
      ensures r = Bag.add x t
      ensures r = Bag.(union t (singleton x)) *)

val f5 : 'a -> 'a t
(*@ r = f5 x
      ensures r = Bag.singleton x *)

val f6 : 'a t -> unit
(*@ f6 t
      ensures forall x: 'a. Bag.(remove x (add x t)) = t *)
