class X::Grammar::Generative::Unable is Exception {
    method message() { "Unable to generate; no matching path found" }
}

# Callback-on-concatenate, used for implementing various anchors.
class CallbackConcat {
    has $.str = '';
    has &.callback_before;
    has &.callback_after;
    method Str() { $!str }
}
multi infix:<~>(CallbackConcat $a, Any $b) {
    $a.callback_after()($a.str ~ $b)
}
multi infix:<~>(Any $a, CallbackConcat $b) {
    $b.callback_before()($a ~ $b.str)
}
multi infix:<~>(CallbackConcat $a, CallbackConcat $b) {
    $a.callback_after()($a.str ~ $b.str)
}

# Drives the overall generation process. "Compiles" by building up trees of
# closures; those actually do the generation work.
my class Generator {
    has Mu $!ast;
    has &!generator;
    
    submethod BUILD(Mu :$ast, :&!generator) {
        $!ast := $ast;
    }
    
    method generate($g, $match) {
        (&!generator //= self.compile($!ast))($g, $match)
    }
    
    method compile(Mu $ast) {
        given $ast.rxtype // 'concat' {
            when 'concat' {
                my @generators = $ast.list.map({ self.compile($^child) });
                return -> $g, $match {
                    sub collect([$gen, *@rest]) {
                        if @rest {
                            gather {
                                my @results := $gen.($g, $match).list;
                                while @results {
                                    my $res = @results.shift;
                                    my @collected := collect(@rest).list;
                                    while @collected {
                                        take $res ~ @collected.shift();
                                    }
                                }
                            }
                        }
                        else {
                            $gen.($g, $match);
                        }
                    }
                    collect @generators
                }
            }
            
            when 'literal' {
                return -> $, $ { [$ast.list[0]] }
            }
            
            when 'altseq' {
                my @generators = $ast.list.map({ self.compile($^child) });
                return -> $g, $match {
                    gather {
                        for @generators -> $altgen {
                            my @results := $altgen.($g, $match).list;
                            while @results {
                                take @results.shift();
                            }
                            CATCH {
                                when X::Grammar::Generative::Unable { }
                            }
                        }
                        X::Grammar::Generative::Unable.new.throw()
                    }
                }
            }
            
            when 'alt' {
                my @generators = $ast.list.map({ self.compile($^child) });
                return -> $g, $match {
                    my @possibles;
                    for @generators -> $altgen {
                        my @results := $altgen.($g, $match);
                        while @results {
                            @possibles.push(@results.shift());
                        }
                        CATCH {
                            when X::Grammar::Generative::Unable { }
                        }
                    }
                    gather {
                        .take for @possibles.sort(-*.chars);
                        X::Grammar::Generative::Unable.new.throw()
                    }
                }
            }
            
            when 'subrule' {
                my $name = $ast.name // '';
                if $name {
                    return self.subrule_call($ast, $name);
                }
                elsif $ast.subtype eq 'method' && (try $ast.list[0].list[0].value eq 'FAILGOAL') {
                    # Bit of a cheat...
                    return -> $, $ { [''] }
                }
                else {
                    die "Unnamed subrule is not yet handled for generation."
                }
            }
            
            when 'subcapture' {
                my $name   = $ast.name // '';
                my $subgen = self.compile($ast.list.[0]);
                return -> $g, $match {
                    if $match{$name} -> $submatch {
                        if $submatch ~~ Capture {
                            $subgen($g, $submatch)
                        }
                        else {
                            [~$submatch]
                        }
                    }
                    elsif $name eq 'sym' {
                        $subgen($g, $match)
                    }
                    else {
                        X::Grammar::Generative::Unable.new.throw()
                    }
                }
            }
            
            when 'quant' {
                my $backtrack = $ast.backtrack // 'g';
                my $quantee := $ast.list.[0];
                my $sep = $ast.list.elems == 2
                    ?? self.compile($ast.list[1])
                    !! Any;
                if ($quantee.rxtype // '') eq 'subrule' | 'subcapture' {
                    return self.subrule_quant($ast, $quantee, $backtrack, $sep);
                }
                else {
                    return -> $g, $match {
                        die "quantifiers other than on subrule/subcapture NYI";
                    }
                }
            }
            
            when 'ws' {
                return self.subrule_call($ast, 'ws');
            }
            
            when 'anchor' {
                return self.anchor($ast.subtype);
            }
            
            default {
                die "Don't know how to generate $_";
            }
        }
    }
    
    method subrule_call(Mu $ast, $name) {
        if $ast.subtype eq 'capture' {
            return -> $g, $match {
                if $match{$name} -> $submatch {
                    if $submatch ~~ Capture {
                        $g.^generator($name).generate($g, $submatch)
                    }
                    else {
                        [~$submatch]
                    }
                }
                elsif $g.^is_gen_proto($name) {
                    $g.^generator($name).generate($g, $match)
                }
                else {
                    X::Grammar::Generative::Unable.new.throw()
                }
            }
        }
        else {
            return -> $g, $match {
                $g.^generator($name).generate($g, \())
            }
        }
    }
    
    method subrule_quant(Mu $ast, Mu $quantee, $backtrack, $sep) {
        my $name := $quantee.name;
        if $name {
            -> $g, $match {
                if $match.hash.exists($name) {
                    my $submatch = $match{$name};
                    if $submatch ~~ List {
                        my $gen = $g.^generator($name);
                        my @matches;
                        for @$submatch {
                            when Capture {
                                @matches.push: $gen.generate($g, $_)
                            }
                            default {
                                @matches.push(~$_);
                            }
                        }
                        [@matches.join($sep ?? $sep($g, $match) !! '')]
                    }
                    else {
                        die "Expected a List for quantified match $name";
                    }
                }
                else {
                    X::Grammar::Generative::Unable.new.throw()
                }
            }
        }
        else {
            die "Unnamed subrule is not yet handled for generation."
        }
    }
    
    method anchor($_) {
        when 'bos' {
            -> $, $ {
                my $cb;
                my $callback_before = -> $str {
                    $str eq '' ?? $cb !! X::Grammar::Generative::Unable.new.throw()
                }
                my $callback_after = -> $str {
                    CallbackConcat.new(:$callback_before, :$callback_after, :$str)
                }
                [$cb = CallbackConcat.new(:$callback_before, :$callback_after)]
            }
        }
        when 'eos' {
            -> $, $ {
                my $cb;
                my $callback_after = -> $str {
                    $str eq '' ?? $cb !! X::Grammar::Generative::Unable.new.throw()
                }
                my $callback_before = -> $str {
                    CallbackConcat.new(:$callback_before, :$callback_after, :$str)
                }
                [$cb = CallbackConcat.new(:$callback_before, :$callback_after)]
            }
        }
        when 'fail' {
            -> $, $ { X::Grammar::Generative::Unable.new.throw() }
        }
        default {
            -> $, $ { [''] }
        }
    }
}

# Hanlding of proto-regex generation (must just delegates).
my class ProtoGenerator {
    has $.name;
    
    method generate($g, $match) {
        my @rules := $g."!protoregex_table"(){$!name};
        for @rules -> $rname {
            if defined $match{$rname} {
                my $submatch = $match{$rname};
                if $submatch ~~ Capture {
                    return $g.^generator($rname).generate($g, $submatch)
                }
                else {
                    return [~$submatch]
                }
            }
        }
        X::Grammar::Generative::Unable.new.throw()
    }
}

# Role automatically mixed into grammars where Grammar::Generative is in
# scope. Provides the generate method, which is the entry point.
my role Generative {
    method generate($match = \(), :$rule = 'TOP', :$g) {
        my @gen := self.^generator($rule).generate(self, $match);
        if $g {
            gather {
                while @gen {
                    take @gen.shift.Str;
                }
                CATCH {
                    when X::Grammar::Generative::Unable { }
                }
            }
        }
        else {
            @gen[0].Str
        }
    }
}

# Some built-in generators for rules inherited from Cursor.
my %builtin_generators =
    ws => Generator.new(generator => -> $, $ { ' ' });

# Replace "grammar" keyword with one that causes Generative to be mixed in
# automatically, plus provides a place to store captured grammar ASTs, etc.
my module EXPORTHOW {
    class grammar is Metamodel::GrammarHOW {
        has %!generators;
        has %!gen_protos;
        
        method new_type(|) {
            my $type := callsame();
            $type.HOW.add_role($type, Generative);
            $type
        }
        
        method save_rx_ast(Mu $obj, $name, Mu $ast) {
            %!generators{$name} = Generator.new(:$ast);
        }
        
        method set_gen_proto(Mu $obj, $name) {
            %!generators{$name} = ProtoGenerator.new(:$name);
            %!gen_protos{$name} = True;
        }
        
        method is_gen_proto(Mu $obj, $name) {
            %!gen_protos{$name}
        }
        
        method generator($obj, $name) {
            %!generators{$name} ||
                %builtin_generators{$name} ||
                    die "Don't know how to generate $name"
        }
    }
}

# Tweak the actions to capture regex declarator AST.
our sub EXPORT() {
    sub setup_ast_capture(%lang) {
        %lang<MAIN-actions> := %lang<MAIN-actions> but role {
            method regex_def(Mu $m) {
                my $nibble := $m.hash<nibble>;
                callsame;
                if $nibble && $*PACKAGE.HOW.HOW.can($*PACKAGE.HOW, 'save_rx_ast') {
                    $*PACKAGE.HOW.save_rx_ast($*PACKAGE, $*DECLARAND.name, $nibble.ast);
                }
                elsif $*MULTINESS eq 'proto' && $*PACKAGE.HOW.HOW.can($*PACKAGE.HOW, 'set_gen_proto') {
                    $*PACKAGE.HOW.set_gen_proto($*PACKAGE, $*DECLARAND.name);
                }
            }
        }
    }
    setup_ast_capture(%*LANG);
    {}
}
