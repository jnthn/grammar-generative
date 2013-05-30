my class Generator {
    has Mu $!ast;
    has &!generator;
    
    submethod BUILD(Mu :$ast) {
        $!ast := $ast;
    }
    
    method generate() {
        (&!generator //= self.compile($!ast))()
    }
    
    method compile(Mu $ast) {
        given $ast.rxtype {
            when 'concat' {
                my @generators = $ast.list.map({ self.compile($^child) });
                return -> { [~] @generators>>.() }
            }
            when 'literal' {
                return -> { $ast.list[0] }
            }
            default {
                die "Don't know how to generate $_";
            }
        }
    }
}

my role Generative {
    method generate(:$rule = 'TOP') {
        self.HOW.generator($rule).generate()
    }
}

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
        
        method generator($name) {
            %!generators{$name} // die "Don't know how to generate $name"
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
