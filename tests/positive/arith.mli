val f1 : int -> int
(*@ y = f1 x
      requires x < max_int
      requires abs x = x
      ensures y = succ x
      ensures y = pow x 42 *)
