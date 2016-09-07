use v6;

my (%macros, %defaults);

my @HTML =
    /\&/ => '&amp;',
    /\</ => '&lt;',
    /\>/ => '&gt;';

my @BS = |@HTML,
    /\\\|/ => '\\',
    /\\\[/ => '[',
    /\\\]/ => ']',
    /\\(\#?\w+)\;/ => { $/ := CALLER::<$/>; "&$0;" }; # bug?

my @ATTR = |@BS,
    /\"/ => '&quot;';

my class Element {
    has $.name;
    has $.attrs;
    method open { "<$!name$!attrs>" }
    method close { "</$!name>" }
    method oc { "<$!name$!attrs/>" }
}

my class MultiElement {
    has @.elements;
    method open { @!elements.map(*.open).join }
    method close { @!elements.reverse.map(*.close).join }
    method oc { self.open ~ self.close }
}

my class Comment {
    method open { '<!--' }
    method close { '-->' }
    method oc { '' }
    method defined { True }
}

my class Dummy {
    method open { '' }
    method close { '' }
    method oc { '' }
    method defined { True }
}

my class Omega is Dummy {
    method element { Dummy }
    method next { self }
    method child { self }
}

my class Node {
    has $.element handles <open close oc tag>;
    has $!next;
    has $!child;
    method next { $!next // self }
    method child { $!child // Omega }
    method set-next($node) { $!next = $node }
    method set-child($node) { $!child = $node }
}

my \INPUT = class {
    also does Iterable;
    also does Iterator;

    my @input = lines.iterator;

    method iterator { self }
    method unshift(\list) { @input.unshift(list.iterator) }
    method shift { @input.shift }
    method pull-one {
        return IterationEnd unless @input;
        my \rv = @input[0].pull-one;
        if rv =:= IterationEnd {
            self.shift;
            self.pull-one;
        }
        else { rv }
    }
}

sub element-from-match($/) {
    my $name = ~$<name>;
    my %attrs = %defaults{$name} // {};
    %attrs{.key} = .value for $<attribute>>>.made;

    Element.new(
        name => ~$<name>,
        attrs => %attrs
            ?? %attrs.map({ " {.key}=\"{.value}\"" }).join
            !! ''
    );
}

my token name { [\w+]+ % '-' }
my token string { [ ['\\' .] | <-[\\\]]>+ ]* }

my token attribute {
    '[' <name> [\h <string>]? ']'
    { make ~$<name> => $<string> ?? $<string>.trans(|@ATTR) !! '' }
}

my token element {
    (<name> <attribute>*)+ % ':'
    {
        make @$0 == 1
            ?? element-from-match($0[0])
            !! MultiElement.new(elements => [ $0.map(&element-from-match) ]);
    }
}

enum <EMPTY NONEMPTY CLOSED>;

my ($block, $row, $cell) = Omega xx *;
my $state = EMPTY;

sub open-block {
    return unless $state == CLOSED;
    put $block.open
        unless $block.element ~~ Dummy;
    $row = $block.child;
    $state = EMPTY;
}

sub close-block {
    return if $state == CLOSED;
    put $state == EMPTY ?? $block.oc !! $block.close
        unless $block.element ~~ Dummy;
    $block = $block.next;
    $state = CLOSED;
}

sub open-row {
    print $row.open;
    $cell = $row.child;
}

sub close-row {
    put $row.close;
    $row = $row.next;
    $state = NONEMPTY;
}

sub open-cell {
    print $cell.open;
}

sub close-cell {
    print $cell.close;
    $cell = $cell.next;
}

my grammar Line {
    token TOP {
    | <.blank>
    | <.rasa>
    | <.macro>
    | <.include>
    | <.default>
    | <.single>
    | <.nested>
    | <.starred>
    | <.heredoc>
    }
    token blank     { $ }
    token rasa      { '\\\\' $ }
    token macro     { '\\macro![' (<[\S]-[\w\[\]]>+) ']' \h (.*) $ }
    token include   { '\\include![' <string> ']' $ }
    token default   { '\\default![' <name> ']' <attribute>+ $ }
    token single    { '\\' <element> $ }
    token nested    { '\\' <tree> $ }
    token starred   { '\\' <tree> '*' $ }
    token heredoc   { '\\' <name> '(' (\w+) ')' <attribute>* [':' <element>]? $ }

    token comment { \! { make Comment } }
    token dummy { <?> { make Dummy } }

    token atom {
        [ <element> | <element=.comment> | <element=.dummy> ]
        { make Node.new(element => $<element>.made) }
    }

    token sublist {
        <node=.tree>+ % \,
        {
            my $first = $<node>[0].made;
            my $prev = $first;
            for $<node>[1..*]>>.made {
                $prev.set-next($_);
                $prev = $_;
            }
            make $first;
        }
    }

    token tree {
        [ <node=.atom> | '{' ~ '}' <node=.sublist> ]+ % '.'
    }
}

my $actions = class {
    method blank($/) {
        close-block;
    }

    method rasa($/) {
        close-block;
        $block = $row = $cell = Omega;
        $state = EMPTY;
    }

    method macro($/) {
        %macros{~$0} = ~$1;
    }

    method include($/) {
        INPUT.unshift($<string>.IO.lines(:close));
    }

    method default($/) {
        my $attrs = %defaults{~$<name>} //= {};
        $attrs{.made.key} = .made.value for $<attribute>;
    }

    method single ($/) {
        close-block;
        put $<element>.made.oc;
    }

    method nested($/) {
        close-block;
        temp $block = $<tree>.made;
        loop {
            $_ := INPUT.pull-one;
            last if $_ =:= IterationEnd || $_ eq '';
            parse-line($_);
        }
        close-block;
    }

    method starred($/) {
        close-block;
        $block = $<tree>.made;
    }

    method heredoc($/) {
        my $marker = ~$0;
        my $element = element-from-match($/);
        $element = do given $<element>.made {
            when Element {
                MultiElement.new(elements => [ $element, $_ ]);
            }
            when MultiElement {
                .elements.unshift($element);
                $_;
            }
        }

        close-block;
        print $element.open;
        loop {
            $_ := INPUT.pull-one;
            last if $_ =:= IterationEnd || $_ eq $marker;
            put .trans(|@HTML);
        }
        put $element.close;
    }

    method tree($/) {
        my $first = $<node>[0].made;
        my $prev = $first;
        for $<node>[1..*]>>.made {
            $prev.set-child($_);
            $prev = $_;
        }
        make $first;
    }
}

sub parse-line($_) {
    open-block;
    open-row;

    for .split(/\t+/) {
        open-cell;
        my @stack;

        print .trans: |@BS,
            / '\\' <element> \h / => {
                @stack.push($<element>.made);
                $<element>.made.open;
            },

            / '\\' <element> [ '\\\\' | $ ] / => {
                $<element>.made.oc;
            },

            / '\\\\' / => {
                @stack ?? @stack.pop.close !! ~$/;
            },

            / \\ (<[\S]-[\w]>+) <name> \; / => {
                ~$0 ~~ %macros
                    ?? %macros{~$0}.subst(:g, '$', ~$<name>)
                    !! ~$/;
            };

        print @stack.pop.close while @stack;
        close-cell;
    }

    close-row;
}

put '<!DOCTYPE html>';
for INPUT {
    LAST close-block;
    Line.parse($_, :$actions) // parse-line($_);
}
