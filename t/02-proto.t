use Grammar::Generative;
use Test;

plan 3;

grammar T01 {
    token TOP { <value> }
    proto token value {*}
    token value:sym<complex> { <re> '+' <im> 'i' }
    token value:sym<integer> { \d+ }
    token value:sym<true>    { <sym> }
}
is T01.generate(\( value => 42 )),
    '42',
    'can specify value for proto name itself';
is T01.generate(\( 'value:sym<complex>' => \( re => 4, im => 9 ) )),
    '4+9i',
    'can specify what to do for fully specifed group name';
is T01.generate(\( 'value:sym<true>' => \() )),
    'true',
    'rules using <sym> work also';
