val f1 : int array -> unit
(*@ f1 a
      requires Array.length a > 0
      requires forall i. 0 <= i < Array.length a -> a.(i) >= 0
      requires Array.for_all (fun x:int -> x >= 0) a
      modifies a
      ensures Array._exists (fun x:int -> x = 42) a
*)

val f2 : 'a array -> 'a array -> 'a array
(*@ c = f2 a b
     ensures c = Array.append a b *)

val f3 : unit -> int array
(*@ a = f3 ()
     ensures Array.length a = 42
     ensures Array.for_all (fun x:int -> x = 0) a *)

val f4 : (int -> int) -> int array
(*@ a = f4 f
     ensures Array.length a = 42
     ensures forall i:int. 0 <= i < Array.length a -> a.(i) = f i
       (* Note: can't have i:integer here, since f expects an int *)
*)
