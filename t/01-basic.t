use Grammar::Generative;
use Test;

plan 4;

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
