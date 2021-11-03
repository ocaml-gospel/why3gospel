  $ why3 config detect > /dev/null

  $ why3 prove *.mli 
  theory Sig
    (* use why3.BuiltIn.BuiltIn *)
    
    (* use why3.Bool.Bool *)
    
    (* use why3.Unit.Unit *)
    
    (* use gospel.Stdlib *)
    
    type t 'a
    
    function view (t 'a) : bag 'a
    
    function to_bag (t:t 'a) : bag 'a = view t
  end
  
  theory Sig1
    (* use why3.BuiltIn.BuiltIn *)
    
    (* use why3.Bool.Bool *)
    
    (* use why3.Unit.Unit *)
    
    (* use gospel.Stdlib *)
  end
  
