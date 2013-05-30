use Grammar::Generative;
use Test;

plan 1;

# JSON::Tiny grammar thanks to moritz++, nabbed for a more realistic test.
grammar JSON::Tiny::Grammar {
    token TOP       { ^ [ <object> | <array> ] $ }
    rule object     { '{' ~ '}' <pairlist>  }
    rule pairlist   { <?> <pair> * % \,             }
    rule pair       { <?> <string> ':' <value>     }
    rule array      { '[' ~ ']' <arraylist>    }
    rule arraylist  { <?> <value>* % [ \, ]        }

    proto token value {*};
    token value:sym<number> {
        '-'?
        [ 0 | <[1..9]> <[0..9]>* ]
        [ \. <[0..9]>+ ]?
        [ <[eE]> [\+|\-]? <[0..9]>+ ]?
    }
    token value:sym<true>    { <sym>    };
    token value:sym<false>   { <sym>    };
    token value:sym<null>    { <sym>    };
    token value:sym<object>  { <object> };
    token value:sym<array>   { <array>  };
    token value:sym<string>  { <string> }

    token string {
        \" ~ \" ( <str> | \\ <str_escape> )*
    }

    token str {
        <-["\\\t\n]>+
    }

    token str_escape {
        <["\\/bfnrt]> | u <xdigit>**4
    }
}

ok JSON::Tiny::Grammar.generate(\(
    object => \(
        pairlist => \(
            pair => [
                \(
                    string              => 'name',
                    'value:sym<string>' => '"Yeti"'
                ),
                \(
                    string              => 'volume',
                    'value:sym<number>' => 9.8
                ),
                \(
                    string              => 'delicious',
                    'value:sym<true>'   => \()
                )
            ]
        ))))
    ~~
    /^ :s '{' 'name' ':' '"Yeti"' ',' 'volume' ':' '9.8' ',' 'delicious' ':' 'true' '}' $/,
    'Basic JSON generation works';
