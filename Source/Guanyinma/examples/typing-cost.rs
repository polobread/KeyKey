//! Headless JSON-line adapter for the repository's fixed typing-cost policy.
//! Original tool, Copyright (c) 2026 Chui-Ping Cheng. MIT License.
use guanyinma::walker::SmartGraph;
use guanyinma::{LearningOptions, ModelDatabase, SmartCandidate, UserSnapshot};
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};

fn state(graph: &SmartGraph, popped: &str) -> Value {
    let segments: Vec<Value> = graph
        .segments()
        .iter()
        .map(|segment| {
            json!({"start": segment.start, "length": segment.span, "text": segment.text,
                   "query": graph.readings()[segment.start..segment.start + segment.span].concat()})
        })
        .collect();
    json!({"text": graph.text(), "popped": popped, "segments": segments})
}

fn command(
    database: &ModelDatabase,
    graph: &mut SmartGraph,
    candidates: &mut Vec<SmartCandidate>,
    line: &str,
) -> Result<Value, Box<dyn std::error::Error>> {
    let (command, argument) = line.split_once('\t').unwrap_or((line, ""));
    match command {
        "reset" => {
            graph.clear();
            candidates.clear();
        }
        "insert" => {
            if argument.len() != 2 || !graph.insert(database, graph.len(), argument)? {
                return Err("unknown reading or insertion failure".into());
            }
            candidates.clear();
        }
        "candidates" => {
            *candidates = graph.candidates_at(argument.parse()?, false);
            return Ok(Value::Array(
                candidates
                    .iter()
                    .map(|candidate| {
                        json!({"start": candidate.start, "length": candidate.span,
                           "text": candidate.text, "query": candidate.query})
                    })
                    .collect(),
            ));
        }
        "select" => {
            let rank: usize = argument.parse()?;
            if !candidates
                .get(rank)
                .is_some_and(|candidate| graph.select(candidate))
            {
                return Err("invalid candidate selection".into());
            }
            candidates.clear();
        }
        "shift" => {
            let popped = graph.shift().ok_or("no segment to shift")?;
            candidates.clear();
            return Ok(state(graph, &popped.text));
        }
        _ => return Err("unknown command".into()),
    }
    Ok(state(graph, ""))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("usage: typing-cost DATABASE")?;
    let database = ModelDatabase::open(path)?;
    let mut graph = SmartGraph::new();
    graph.set_user_data(
        &database,
        &UserSnapshot::default(),
        LearningOptions {
            user_phrases: false,
            candidate_overrides: false,
            bigrams: false,
            table_learning: false,
        },
    )?;
    let mut candidates = Vec::new();
    let stdout = io::stdout();
    let mut output = stdout.lock();
    for line in io::stdin().lock().lines() {
        let value = match command(&database, &mut graph, &mut candidates, &line?) {
            Ok(value) => value,
            Err(error) => json!({"error": error.to_string()}),
        };
        writeln!(output, "{value}")?;
        output.flush()?;
    }
    Ok(())
}
