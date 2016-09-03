use v6;

my @HTML =
    /\&/ => '&amp;',
    /\</ => '&lt;',
    /\>/ => '&gt;';

my @BS = |@HTML,
    /\\\|/ => '\\',
    /\\\[/ => '[',
    /\\\]/ => ']',
    /\\(\#?\w+)\;/ => { "&$0;" };

my @ATTR = |@BS,
    /\"/ => '&quot;';

my class Element {
    has $.name;
    has $.attrs;
    has $.tag;
    method open { "<$!name$!attrs>" }
    method close { "</$!name>" }
    method oc { "<$!name$!attrs/>" }
}

my class Multi {
    has @.elements;
    method open { @!elements.map(*.open).join }
    method close { @!elements.reverse.map(*.close).join }
    method oc { self.open ~ self.close }
    method tag { @!elements[0].tag }
}

my class Comment {
    method open { '<!--' }
    method close { '-->' }
    method oc { '' }
    method tag { Nil }
}

my class Dummy {
    method open { '' }
    method close { '' }
    method oc { '' }
    method tag { Nil }
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
    submethod BUILD(:$!element, :$!next, :$!child) {}
    method next { $!next // self }
    method child { $!child // Omega }
    method set-next($node) { $!next = $node }
    method set-child($node) { $!child = $node }
}

my token name {
    [\w+]+ % \-
}

my token attribute {
    \[ <name> [ \h ([ [ \\. ] | <-[\\\]]>+ ]*) ]? \]
    { make "$<name>=\"{ $0 ?? $0.trans(|@ATTR) !! '' }\"" }
}

my token attributes {
    <attribute>*
    { make $<attribute> ?? ' ' ~ $<attribute>>>.made.join(' ') !! '' }
}

my token single($tagged = False) {
    <name> [ <!{$tagged}> || \( <tag=&name> \) ] <attributes>
    {
        make Element.new(name => ~$<name>, attrs => $<attributes>.made,
            tag => $tagged ?? ~$<tag> !! Nil);
    }
}

my token element(:$tagged = False) {
    <single($tagged)> [ \: <multi=&single> ]*
    {
        make $<multi>
            ?? Multi.new(:elements($<single>.made, |$<multi>>>.made))
            !! $<single>.made;
    }
}

my token comment { \! { make Comment } }
my token dummy { <?> { make Dummy } }

my token atom {
    [ <element> | <element=&comment> | <element=&dummy> ]
    { make Node.new(element => $<element>.made) }
}

my token sublist {
    <node=&tree>+ % \,
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

my token tree {
    [ <node=&atom> | \{ ~ \} <node=&sublist> ]+ % \.
    {
        my $first = $<node>[0].made;
        my $prev = $first;
        for $<node>[1..*]>>.made {
            $prev.set-child($_);
            $prev = $_;
        }
        make $first;
    }
}

my $block = Omega;
my $row = Omega;
my $closed = False;

sub open-block {
    return unless $closed;
    put $block.open unless $block.element ~~ Dummy;
    $row = $block.child;
    $closed = False;
}

sub close-block {
    return if $closed;
    put $block.close unless $block.element ~~ Dummy;
    $block = $block.next;
    $closed = True;
}

put '<!DOCTYPE html>';

my %macros;
for lines() {
    LAST close-block;

    when defined $block.tag {
        when $block.tag {
            put $block.close;
            $block = Omega;
            $closed = False;
        }
        default { put .trans(|@HTML) }
    }

    when /^$/ {
        close-block;
    }

    when /^ \\\\ $/ {
        close-block;
        $block = Omega;
    }

    when /^ \\macro\! \[ (<[\S]-[\w]>+) \] \h (.*) $/ {
        %macros{~$0} = ~$1;
    }

    when /^ '\\---' $/ {
        put "<hr/>";
    }

    when /^ \\ <element(:tagged)> $/ {
        close-block;
        $block = $<element>.made;
        print $block.open;
    }

    when /^ \\ <tree> \* $/ {
        close-block;
        $block = $<tree>.made;
    }

    default {
        open-block;
        print $row.open;

        my $field = $row.child;
        for .split(/\t+/) {
            print $field.open;

            my @stack;
            print .trans: |@BS,
                / \\ [ <element> | <element=&comment> ] \h / => {
                    @stack.push($<element>.made);
                    $<element>.made.open;
                },

                / \\ <element> [ \\\\ | $ ] / => {
                    $<element>.made.oc;
                },

                / \\\\ / => {
                    @stack ?? @stack.pop.close !! ~$/;
                },

                / \\ (<[\S]-[\w]>+) <name> \; / => {
                    ~$0 ~~ %macros
                        ?? %macros{~$0}.subst(:g, '$', ~$<name>)
                        !! ~$/;
                };

            print @stack.pop.close while @stack;
            print $field.close;
            $field = $field.next;
        }

        put $row.close;
        $row = $row.next;
    }
}
