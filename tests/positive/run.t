  $ why3 config detect > /dev/null

  $ why3 prove bag_stdlib.mli
  theory Bag_stdlib
    (* use why3.BuiltIn.BuiltIn *)

    (* use why3.Bool.Bool *)

    (* use why3.Unit.Unit *)

    (* use gospel.Gospelstdlib *)

    type t 'a

    function view (t 'a) : bag 'a

    function to_bag (t:t 'a) : bag 'a = view t
  end

  $ why3 prove list_stdlib.mli
  theory List_stdlib
    (* use why3.BuiltIn.BuiltIn *)

    (* use why3.Bool.Bool *)

    (* use why3.Unit.Unit *)

    (* use gospel.Gospelstdlib *)
  end

  $ why3 prove arith.mli
  theory Arith_stdlib
    (* use why3.BuiltIn.BuiltIn *)

    (* use why3.Bool.Bool *)

    (* use why3.Unit.Unit *)

    (* use gospel.Stdlib *)
  end

  $ why3 prove arrays.mli
  theory Arrays
    (* use why3.BuiltIn.BuiltIn *)

    (* use why3.Bool.Bool *)

    (* use why3.Unit.Unit *)

    (* use gospel.Gospelstdlib *)
  end
