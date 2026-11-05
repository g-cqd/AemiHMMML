--------------------------- MODULE YAMLSimpleKeys ---------------------------
(***************************************************************************)
(* The simple-key protocol of YAMLScanner (Sources/AemiYAML/YAMLScanner.swift, fetchMoreTokens, saveSimpleKey;    *)
(* YAMLScanner+Fetch.swift, fetchValue): a node that may turn out to be a key is remembered with its token's      *)
(* number; when its ':' arrives, a KEY token is inserted in front of it. The parser takes tokens from the queue  *)
(* meanwhile, so the queue must hold back a token that may still get a KEY in front of it.                       *)
(*                                                                                                               *)
(* Inputs: every sequence of up to MaxLen lexemes of a flow sequence: a node, a ':' value indicator, a ',' entry    *)
(* separator, a line break (which makes a waiting key stale: these implicit keys are one line). A key may start   *)
(* only where one is allowed (saveSimpleKey's simpleKeyAllowed): at the start and after ','; not after a node or  *)
(* a ':', so a second node on the line leaves the first one waiting (libyaml does the same; the parser then       *)
(* refuses the input). Checked: a KEY is never inserted behind what the parser has taken, and the tokens the parser takes are  *)
(* the ones an independent, queue-free definition gives.                                                          *)
(*                                                                                                               *)
(* YAMLSimpleKeyOracleTests runs the real scanner over the same inputs (in a flow sequence) against the same      *)
(* definition. The .buggy.cfg lets the parser take a token without the hold-back (TakeEagerly = TRUE).           *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS MaxLen, TakeEagerly

Lexemes == {"node", "colon", "comma", "break"}
AllInputs == UNION {[1..k -> Lexemes] : k \in 0..MaxLen}

VARIABLES input, pos, queue, produced, parsed, key, allowed, out, behind

vars == <<input, pos, queue, produced, parsed, key, allowed, out, behind>>

Init ==
    /\ input \in AllInputs
    /\ pos = 1
    /\ queue = <<>>
    /\ produced = 0
    /\ parsed = 0
    /\ key = [possible |-> FALSE, number |-> 0]
    /\ allowed = TRUE
    /\ out = <<>>
    /\ behind = FALSE

\* The scanner fetches only when the parser waits: the queue is empty, or its head may still get a KEY in front of it.
NeedsMore == queue = <<>> \/ (key.possible /\ key.number = parsed)

InsertAt(s, i, e) == SubSeq(s, 1, i - 1) \o <<e>> \o SubSeq(s, i, Len(s))

Fetch ==
    /\ pos <= Len(input) + 1
    /\ NeedsMore
    /\ IF pos = Len(input) + 1
       THEN /\ queue' = Append(queue, "end")
            /\ produced' = produced + 1
            /\ UNCHANGED <<key, allowed, behind>>
       ELSE CASE input[pos] = "node" ->
                    /\ key' = IF allowed THEN [possible |-> TRUE, number |-> produced] ELSE key
                    /\ allowed' = FALSE
                    /\ queue' = Append(queue, "scalar")
                    /\ produced' = produced + 1
                    /\ UNCHANGED behind
              [] input[pos] = "colon" /\ key.possible ->
                    \* The KEY goes where the key's token is: its number less the tokens already taken. If the parser took
                    \* that token already, there is nowhere to put it: the violation is recorded and the KEY lost.
                    /\ behind' = (key.number < parsed)
                    /\ queue' = IF key.number < parsed THEN Append(queue, "value")
                                ELSE Append(InsertAt(queue, key.number - parsed + 1, "key"), "value")
                    /\ produced' = produced + 2
                    /\ key' = [key EXCEPT !.possible = FALSE]
                    /\ allowed' = FALSE
              [] input[pos] = "colon" ->
                    /\ queue' = Append(queue, "value")
                    /\ produced' = produced + 1
                    /\ allowed' = FALSE
                    /\ UNCHANGED <<key, behind>>
              [] input[pos] = "comma" ->
                    /\ queue' = Append(queue, "entry")
                    /\ produced' = produced + 1
                    /\ key' = [key EXCEPT !.possible = FALSE]
                    /\ allowed' = TRUE
                    /\ UNCHANGED behind
              [] input[pos] = "break" ->
                    /\ key' = [key EXCEPT !.possible = FALSE]
                    /\ UNCHANGED <<queue, produced, allowed, behind>>
    /\ pos' = pos + 1
    /\ UNCHANGED <<input, parsed, out>>

Take ==
    /\ queue /= <<>>
    /\ TakeEagerly \/ ~NeedsMore \/ pos > Len(input) + 1
    /\ out' = Append(out, Head(queue))
    /\ queue' = Tail(queue)
    /\ parsed' = parsed + 1
    /\ UNCHANGED <<input, pos, produced, key, allowed, behind>>

Done == pos > Len(input) + 1 /\ queue = <<>>

Next == Fetch \/ Take \/ (Done /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars /\ WF_vars(Fetch \/ Take)

\* The tokens, without a queue: a node is claimed as a key when it stands where a key may start (only breaks between it and
\* the start or the last ',') and a later ':' follows with no break, ',' or ':' between; a claimed node is KEY, scalar,
\* any other a scalar; a ':' is a VALUE, a ',' an entry.
MayStartKey(s, i) == \A j \in 1..(i - 1) : s[j] \in {"break", "comma"} \/ \E k \in (j + 1)..(i - 1) : s[k] = "comma"
Claimed(s, j) ==
    /\ s[j] = "node"
    /\ MayStartKey(s, j)
    /\ \E i \in (j + 1)..Len(s) : s[i] = "colon" /\ \A k \in (j + 1)..(i - 1) : s[k] \notin {"break", "comma", "colon"}

RECURSIVE Expected(_, _)
Expected(s, i) ==
    IF i > Len(s) THEN <<"end">>
    ELSE LET here == CASE s[i] = "node" /\ Claimed(s, i) -> <<"key", "scalar">>
                       [] s[i] = "node" -> <<"scalar">>
                       [] s[i] = "colon" -> <<"value">>
                       [] s[i] = "comma" -> <<"entry">>
                       [] s[i] = "break" -> <<>>
         IN here \o Expected(s, i + 1)

NeverBehind == ~behind
Agrees == Done => out = Expected(input, 1)
Terminates == <>Done
=============================================================================
