open Core_kernel
open IECCheckerCore
open IECCheckerParser
open IECCheckerLib
open IECCheckerAnalysis
module S = Syntax
module Lib = CheckerLib
module TI = Tok_info
module W = Warn
module WO = Warn_output

let print_position outx (lexbuf : Lexing.lexbuf) =
  let pos = lexbuf.lex_curr_p in
  Printf.fprintf outx "%s:%d:%d" pos.pos_fname pos.pos_lnum
    (pos.pos_cnum - pos.pos_bol)

let parse_with_error lexbuf =
  let tokinfo lexbuf = TI.create lexbuf in
  let l = Lexer.initial tokinfo in
  try Parser.main l lexbuf with
  | Lexer.LexingError msg ->
    fprintf stderr "%a: %s\n" print_position lexbuf msg;
    []
  | Parser.Error ->
    Printf.fprintf stderr "%a: syntax error\n" print_position lexbuf;
    []
  | Failure msg ->
    Printf.fprintf stderr "%a: %s-n" print_position lexbuf msg;
    []

let parse_elements lexbuf =
  let node = parse_with_error lexbuf in
  match node with elements -> elements

let parse_file (filename : string) : S.iec_library_element list =
  let inx = In_channel.create filename in
  let lexbuf = Lexing.from_channel inx in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  let elements = parse_elements lexbuf in
  In_channel.close inx;
  elements

let run_checker filename fmt create_dumps quiet =
  if not (Sys.file_exists filename) then
    failwith ("File " ^ filename ^ " doesn't exists")
  else
    let elements = parse_file filename in
    let envs = Ast_util.create_envs elements in
    if create_dumps then
      Ast_util.create_dump elements envs filename;
    let pou_cfgs = Cfg.create_cfgs elements in
    let decl_warnings = Declaration_analysis.run elements envs in
    let flow_warnings = Control_flow_analysis.run pou_cfgs in
    let lib_warnings = Lib.run_all_checks elements envs quiet in
    WO.print_report (decl_warnings @ flow_warnings @ lib_warnings) fmt

let command =
  Command.basic ~summary:"IEC61131-3 static analysis"
    Command.Let_syntax.(
      let%map_open
        output_format = flag "-output-format" (optional string) ~doc:"Output format"
      and
        create_dumps = flag "-dump" (optional bool) ~doc:"Generate AST dumps in JSON format"
      and
        quiet = flag "-quiet" (optional bool) ~doc:"Print only error messages."
      and
        files = anon (sequence ("filename" %: Core.Filename.arg_type))
      in
      fun () ->
        let fmt = match output_format with
          | Some s -> (
              if String.equal s "json" then
                WO.Json
              else if String.equal s "plain" then
                WO.Plain
              else (
                Printf.eprintf "Unknown output format '%s'!\n\n" s;
                Printf.eprintf "Supported formats:\n" ;
                Printf.eprintf "  plain\n" ;
                Printf.eprintf "  json\n" ;
                exit 22
              ))
          | None -> WO.Plain
        in
        let create_dumps = match create_dumps with
          | Some v -> v
          | None -> false
        in
        let quiet = match quiet with
          | Some v -> v
          | None -> false
        in
        match files with
        | [] -> (
            Printf.eprintf "No input files\n";
            exit 1)
        | _ -> List.iter files ~f:(fun f -> run_checker f fmt create_dumps quiet)
    )

let () =
  Core.Command.run command
