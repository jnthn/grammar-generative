use Grammar::Generative;
use Test;

plan 1;

grammar T01 {
    token TOP { dog }
}

is T01.generate(), 'dog', 'can generate literal';
