use Grammar::Generative;
use Test;

plan 16;

grammar T01 {
    token TOP { dog }
}
is T01.generate(), 'dog', 'can generate literal';

grammar T02 {
    token TOP { <sentence> }
    token sentence { <subject> ' ' <verb> ' ' <object> '.' }
}
is T02.generate(\(
    sentence => \(
        subject => 'Petrucci',
        verb    => 'plays',
        object  => 'guitar'
    ))),
    'Petrucci plays guitar.',
    'simple subrule/capture handling';

grammar T03 {
    token TOP { <sentence> }
    token sentence {
        || <subject> ' ' <verb> ' ' <object> '.'
        || <subject> ' ' <verb> '.'
    }
}
is T03.generate(\(
    sentence => \(
        subject => 'Man',
        verb    => 'bites',
        object  => 'dog'
    ))),
    'Man bites dog.',
    'capture/altseq interaction';
is T03.generate(\(
    sentence => \(
        subject => 'It',
        verb    => 'rained'
    ))),
    'It rained.',
    'capture/altseq interaction';
{
    my @all = T03.generate(\(
        sentence => \(
            subject => 'Man',
            verb    => 'bites',
            object  => 'dog'
        )), :g);
    is +@all, 2, 'altseq visits both possibles in :g mode';
    is @all[0], 'Man bites dog.', 'first alt is correct';
    is @all[1], 'Man bites.', 'second alt is correct';
}

grammar T04 {
    token TOP { $<re>=[\d+] '+' $<im>=[\d+] 'i' }
}
is T04.generate(\(re => 5, im => 9)),
    '5+9i',
    'subcapture';

grammar T05 {
    token TOP { <num>* % ', ' }
    token num { \d+ }
}
is T05.generate(\(
        num => [5, 19, 21, 8]
    )),
    '5, 19, 21, 8',
    'quant with list specified';

grammar T06 {
    token TOP { <comp>* % ' * ' }
    token comp { $<re>=[\d+] '+' $<im>=[\d+] 'i' }
}
is T06.generate(\(
        comp => [
            \( re => 8, im => 2 ),
            \( re => 7, im => 45 )
        ]
    )),
    '8+2i * 7+45i',
    'quant with list specified';

grammar T07 {
    token TOP { <sentence> }
    token sentence {
        | <subject> ' ' <verb> '.'
        | <subject> ' ' <verb> ' ' <object> '.'
    }
}
is T07.generate(\(
    sentence => \(
        subject => 'Man',
        verb    => 'bites'
    ))),
    'Man bites.',
    'alt works when we hit first case';
is T07.generate(\(
    sentence => \(
        subject => 'Man',
        verb    => 'bites',
        object  => 'dog'
    ))),
    'Man bites dog.',
    'alt picks correct thing even when second';

grammar T08 {
    token TOP { <sentence> }
    rule sentence {<subject> <verb> :!s <object> '.' }
}
is T08.generate(\(
    sentence => \(
        subject => 'Petrucci',
        verb    => 'plays',
        object  => 'guitar'
    ))),
    'Petrucci plays guitar.',
    'rules/<.ws>';

grammar T09 { token TOP { ^ foo $ } }
is T09.generate(), 'foo', '^ and $ (unviolated case)';

grammar T10 { token TOP { a ^ foo $ } }
dies-ok { T10.generate() }, '^ and $ (^ violated)';

grammar T11 { token TOP { ^ foo $ 'x' } }
dies-ok { T11.generate() }, '^ and $ ($ violated)';
