class X::Grammar::Generative::Unable is Exception { }

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
        given $ast.rxtype {
            when 'concat' {
                my @generators = $ast.list.map({ self.compile($^child) });
                return -> $g, $match {
                    sub collect([$gen, *@rest]) {
                        if @rest {
                            gather for $gen.($g, $match) -> $res {
                                for collect(@rest) -> $next {
                                    take $res ~ $next;
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
                            for $altgen.($g, $match) -> $res {
                                take $res;
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
                        for $altgen.($g, $match) -> $res {
                            @possibles.push($res);
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
                my $name = $ast.name;
                if $name {
                    return self.subrule_call($ast, $name);
                }
                else {
                    die "Unnamed subrule is not yet handled for generation."
                }
            }
            
            when 'subcapture' {
                my $name   = $ast.name;
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
                if $quantee.rxtype eq 'subrule' | 'subcapture' {
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
                $cb = CallbackConcat.new(:$callback_before, :$callback_after)
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
                $cb = CallbackConcat.new(:$callback_before, :$callback_after)
            }
        }
        when 'fail' {
            -> $, $ { X::Grammar::Generative::Unable.new.throw() }
        }
        default {
            -> $, $ { '' }
        }
    }
}

my role Generative {
    method generate($match = \(), :$rule = 'TOP', :$g) {
        my @gen := self.^generator($rule).generate(self, $match);
        if $g {
            gather {
                while @gen {
                    take @gen.shift;
                }
                CATCH {
                    when X::Grammar::Generative::Unable { }
                }
            }
        }
        else {
            @gen[0]
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
        
        method new_type(|) {
            my $type := callsame();
            $type.HOW.add_role($type, Generative);
            $type
        }
        
        method save_rx_ast(Mu $obj, $name, Mu $ast) {
            %!generators{$name} = Generator.new(:$ast);
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
                my $ast := $m.hash<nibble>.ast;
                callsame;
                if $*PACKAGE.HOW.HOW.can($*PACKAGE.HOW, 'save_rx_ast') {
                    $*PACKAGE.HOW.save_rx_ast($*PACKAGE, $*DECLARAND.name, $ast);
                }
            }
        }
    }
    setup_ast_capture(%*LANG);
    {}
}
