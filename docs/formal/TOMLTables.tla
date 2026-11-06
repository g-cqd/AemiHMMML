----------------------------- MODULE TOMLTables -----------------------------
(***************************************************************************)
(* TOML's table rules as TOMLParser+Tables.swift applies them: every table and value is a node with a parent, a    *)
(* name, a kind and an origin (implicit on a header's way, defined by a header, by dotted keys, inline, an array   *)
(* written as a value, an array of tables), and dotted keys carry the section (the header) they were written in. *)
(*                                                                                                               *)
(* Inputs: every sequence of up to MaxLen statements over the keys a, b, a.a, a.b, b.a, b.b: a header [k], an      *)
(* array-of-tables header [[k]], a key/value k = 1 and an inline table k = {} (closed at once), keys relative to   *)
(* the current table. A statement the rules refuse ends the document (the parser is strict).                      *)
(*                                                                                                               *)
(* Checked on every reachable state: a table is defined at most once (TOML 1.1: "you cannot define a table more     *)
(* than once"; dotted keys define the tables they create, a header the one it names, unless only implied); no key    *)
(* is in a table twice; nothing is added under a value or to an inline table; an array of tables grows only by     *)
(* [[ ]]. And the spec's own examples are accepted: dotted keys then a header for a sub-table ([fruit.apple.texture]) *)
(* and an implied table defined later.                                                                            *)
(*                                                                                                               *)
(* TOMLTableOracleTests runs AemiTOML over the same inputs against the same rules. The .buggy.cfg lets a header      *)
(* redefine a table dotted keys made ([fruit.apple] after apple.color = ..., which the spec forbids).              *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS MaxLen, AllowHeaderOverDotted

Names == {"a", "b"}
Keys == {<<n>> : n \in Names} \cup {<<n, m>> : n \in Names, m \in Names}
Statements == [kind : {"header", "array", "value", "inline"}, key : Keys]
AllInputs == UNION {[1..k -> Statements] : k \in 0..MaxLen}

\* Node 1 is the root table, defined by the document itself.
Root == [name |-> "", parent |-> 0, kind |-> "table", origin |-> "header", section |-> 0, defs |-> 1, grown |-> FALSE]

VARIABLES input, pos, nodes, current, section, failed

vars == <<input, pos, nodes, current, section, failed>>

Init ==
    /\ input \in AllInputs
    /\ pos = 1
    /\ nodes = <<Root>>
    /\ current = 1
    /\ section = 0
    /\ failed = FALSE

\* The child of t named n (an array's elements are unnamed), or 0.
Find(t, n) == IF \E i \in DOMAIN nodes : nodes[i].parent = t /\ nodes[i].name = n
              THEN CHOOSE i \in DOMAIN nodes : nodes[i].parent = t /\ nodes[i].name = n ELSE 0

\* An array of tables' last element: what a header's path enters.
LastElement(a) == CHOOSE i \in DOMAIN nodes : nodes[i].parent = a /\ \A j \in DOMAIN nodes : nodes[j].parent = a => j <= i

New(name, parent, kind, origin) ==
    [name |-> name, parent |-> parent, kind |-> kind, origin |-> origin, section |-> section,
     defs |-> IF origin = "implicit" THEN 0 ELSE 1, grown |-> FALSE]

\* Where a header's first part leads, from the root: the table it names (made implicit when missing), the last element
\* of an array of tables, or 0 when it names a value, an array written as a value or an inline table. The node made, if any.
HeaderParent(k) ==
    IF Len(k) = 1 THEN <<1, <<>>>>
    ELSE LET f == Find(1, k[1]) IN
         IF f = 0 THEN <<Len(nodes) + 1, <<New(k[1], 1, "table", "implicit")>>>>
         ELSE IF nodes[f].kind = "table" /\ nodes[f].origin # "inline" THEN <<f, <<>>>>
         ELSE IF nodes[f].kind = "array" /\ nodes[f].origin = "tables" THEN <<LastElement(f), <<>>>>
         ELSE <<0, <<>>>>

Fail == /\ failed' = TRUE
        /\ UNCHANGED <<nodes, current, section>>

Header(k) ==
    LET walk == HeaderParent(k)
        made == nodes \o walk[2]
        parent == walk[1]
        g == IF parent = 0 THEN 0 ELSE
             IF \E i \in DOMAIN made : made[i].parent = parent /\ made[i].name = k[Len(k)]
             THEN CHOOSE i \in DOMAIN made : made[i].parent = parent /\ made[i].name = k[Len(k)] ELSE 0
    IN IF parent = 0 THEN Fail
       ELSE IF g = 0 THEN
           /\ nodes' = Append(made, New(k[Len(k)], parent, "table", "header"))
           /\ current' = Len(made) + 1
           /\ section' = section + 1
           /\ failed' = FALSE
       ELSE IF made[g].kind = "table" /\ (made[g].origin = "implicit" \/ (AllowHeaderOverDotted /\ made[g].origin = "dotted"))
       THEN \* An implied table defined now (or, in the buggy model, a dotted one defined again).
           /\ nodes' = [made EXCEPT ![g].origin = "header", ![g].defs = @ + 1]
           /\ current' = g
           /\ section' = section + 1
           /\ failed' = FALSE
       ELSE Fail

ArrayHeader(k) ==
    LET walk == HeaderParent(k)
        made == nodes \o walk[2]
        parent == walk[1]
        g == IF parent = 0 THEN 0 ELSE
             IF \E i \in DOMAIN made : made[i].parent = parent /\ made[i].name = k[Len(k)]
             THEN CHOOSE i \in DOMAIN made : made[i].parent = parent /\ made[i].name = k[Len(k)] ELSE 0
    IN IF parent = 0 THEN Fail
       ELSE IF g = 0 THEN
           LET withArray == Append(made, New(k[Len(k)], parent, "array", "tables"))
           IN /\ nodes' = Append(withArray, New("", Len(withArray), "table", "header"))
              /\ current' = Len(withArray) + 1
              /\ section' = section + 1
              /\ failed' = FALSE
       ELSE IF made[g].kind = "array" /\ made[g].origin = "tables" THEN
           /\ nodes' = Append([made EXCEPT ![g].grown = TRUE], New("", g, "table", "header"))
           /\ current' = Len(made) + 1
           /\ section' = section + 1
           /\ failed' = FALSE
       ELSE Fail

\* k = 1 or k = {} under the current table: a dotted key's first part must be a table dotted keys made in this section.
Assign(k, inline) ==
    LET f == IF Len(k) = 2 THEN Find(current, k[1]) ELSE 0
        made == IF Len(k) = 2 /\ f = 0 THEN Append(nodes, New(k[1], current, "table", "dotted")) ELSE nodes
        parent == IF Len(k) = 1 THEN current
                  ELSE IF f = 0 THEN Len(made)
                  ELSE IF nodes[f].kind = "table" /\ nodes[f].origin = "dotted" /\ nodes[f].section = section THEN f
                  ELSE 0
        taken == \E i \in DOMAIN made : made[i].parent = parent /\ made[i].name = k[Len(k)]
    IN IF parent = 0 \/ taken THEN Fail
       ELSE /\ nodes' = Append(made, IF inline THEN New(k[Len(k)], parent, "table", "inline")
                                    ELSE New(k[Len(k)], parent, "value", "value"))
            /\ failed' = FALSE
            /\ UNCHANGED <<current, section>>

Step ==
    /\ ~failed
    /\ pos <= Len(input)
    /\ pos' = pos + 1
    /\ UNCHANGED input
    /\ LET s == input[pos] IN
       CASE s.kind = "header" -> Header(s.key)
         [] s.kind = "array" -> ArrayHeader(s.key)
         [] s.kind = "value" -> Assign(s.key, FALSE)
         [] s.kind = "inline" -> Assign(s.key, TRUE)

Done == (failed \/ pos > Len(input)) /\ UNCHANGED vars

Spec == Init /\ [][Step \/ Done]_vars /\ WF_vars(Step)

-----------------------------------------------------------------------------
DefinedOnce == \A i \in DOMAIN nodes : nodes[i].defs <= 1

KeysUnique == \A i, j \in DOMAIN nodes :
    (i # j /\ nodes[i].parent = nodes[j].parent /\ nodes[i].name # "") => nodes[i].name # nodes[j].name

NothingUnderValues == \A i \in DOMAIN nodes : nodes[i].parent # 0 =>
    /\ nodes[nodes[i].parent].kind # "value"
    /\ nodes[nodes[i].parent].origin # "inline"

\* An array's elements are tables only an array-of-tables header adds.
ArraysOfTables == \A i \in DOMAIN nodes : (nodes[i].parent # 0 /\ nodes[nodes[i].parent].kind = "array") =>
    /\ nodes[nodes[i].parent].origin = "tables"
    /\ nodes[i].kind = "table" /\ nodes[i].name = ""

\* TOML 1.1's own valid examples, in this alphabet, are read to the end.
Examples == {
    \* a.a = 1 then [a.b]: dotted keys made a, and a header adds a sub-table to it ([fruit.apple.texture]).
    <<[kind |-> "value", key |-> <<"a", "a">>], [kind |-> "header", key |-> <<"a", "b">>]>>,
    \* [a.b] then [a]: a table only implied may be defined later.
    <<[kind |-> "header", key |-> <<"a", "b">>], [kind |-> "header", key |-> <<"a">>]>>,
    \* [[a]] twice, each with its key: two elements.
    <<[kind |-> "array", key |-> <<"a">>], [kind |-> "value", key |-> <<"b">>], [kind |-> "array", key |-> <<"a">>]>>
}
ExamplesAccepted == input \in Examples => ~failed

Terminates == <>(failed \/ pos > Len(input))
=============================================================================
