-------------------------- MODULE YAMLIndentation --------------------------
(***************************************************************************)
(* The block indentation stack of YAMLScanner (Sources/AemiYAML/YAMLScanner.swift, rollIndent and unrollIndent): *)
(* a line whose first token is a block indicator ("-", or a key and its ':') at column c first closes every open  *)
(* collection deeper than c, then opens one at c if the innermost is shallower. At the end, all close.            *)
(*                                                                                                               *)
(* Inputs: every document of up to MaxLines lines, each at a column in 0..MaxCol, an entry or a key. Checked: the *)
(* stack strictly deepens; a collection is never closed and reopened at its own column; and the tokens are the   *)
(* ones an independent definition gives, which uses no stack: the columns open before line i are those of        *)
(* earlier lines no shallower line has interrupted since; line i closes the open ones deeper than itself, and     *)
(* opens a collection exactly when its own column is not open.                                                   *)
(*                                                                                                               *)
(* YAMLIndentationOracleTests runs the real scanner over the same documents against the same definition. The     *)
(* .buggy.cfg closes collections at the line's own column too (CloseAtSameColumn = TRUE: '>=' for '>').          *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS MaxLines, MaxCol, CloseAtSameColumn

Lines == (0..MaxCol) \X {"entry", "key"}
AllInputs == UNION {[1..k -> Lines] : k \in 0..MaxLines}

VARIABLES input, line, stack, out, phase

vars == <<input, line, stack, out, phase>>

Init ==
    /\ input \in AllInputs
    /\ line = 1
    /\ stack = <<>>
    /\ out = <<>>
    /\ phase = "unroll"

Top == IF stack = <<>> THEN -1 ELSE stack[Len(stack)]
Column == IF line > Len(input) THEN -1 ELSE input[line][1]
Closes(top, c) == IF CloseAtSameColumn THEN top >= c /\ top >= 0 ELSE top > c

\* One collection closes per step, as unrollIndent's loop does.
Unroll ==
    /\ phase = "unroll"
    /\ IF Closes(Top, Column) /\ stack /= <<>>
       THEN /\ out' = Append(out, <<"end", Top, line>>)
            /\ stack' = SubSeq(stack, 1, Len(stack) - 1)
            /\ UNCHANGED phase
       ELSE /\ phase' = IF line > Len(input) THEN "done" ELSE "roll"
            /\ UNCHANGED <<stack, out>>
    /\ UNCHANGED <<input, line>>

Roll ==
    /\ phase = "roll"
    /\ IF Top < Column
       THEN /\ stack' = Append(stack, Column)
            /\ out' = Append(out, <<input[line][2], Column, line>>)
       ELSE UNCHANGED <<stack, out>>
    /\ line' = line + 1
    /\ phase' = "unroll"
    /\ UNCHANGED input

Next == Unroll \/ Roll \/ (phase = "done" /\ UNCHANGED vars)

Spec == Init /\ [][Next]_vars /\ WF_vars(Unroll \/ Roll)

\* Without a stack: the columns open before line i.
OpenBefore(s, i) == {s[j][1] : j \in {j \in 1..(i - 1) : \A k \in (j + 1)..(i - 1) : s[k][1] >= s[j][1]}}

RECURSIVE Descending(_, _)
Descending(set, i) == IF set = {} THEN <<>>
                      ELSE LET m == CHOOSE m \in set : \A n \in set : m >= n
                           IN <<<<"end", m, i>>>> \o Descending(set \ {m}, i)

RECURSIVE Expected(_, _)
Expected(s, i) ==
    IF i > Len(s) THEN Descending(OpenBefore(s, i), i)
    ELSE LET c == s[i][1]
             closes == Descending({o \in OpenBefore(s, i) : o > c}, i)
             opens == IF c \in OpenBefore(s, i) THEN <<>> ELSE <<<<s[i][2], c, i>>>>
         IN closes \o opens \o Expected(s, i + 1)

Deepens == \A i \in 1..(Len(stack) - 1) : stack[i] < stack[i + 1]
\* No line closes the collection at its own column and opens another there.
NoReopen == \A i, j \in 1..Len(out) :
    ~(out[i][1] = "end" /\ out[j][1] /= "end" /\ out[i][2] = out[j][2] /\ out[i][3] = out[j][3])
Agrees == phase = "done" => out = Expected(input, 1)
Terminates == <>(phase = "done")
=============================================================================
