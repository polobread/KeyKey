#!/usr/bin/env python3
"""Rebuild the selected project unigram and paired 800-article bigram model."""
import argparse
import importlib.util
import json
from pathlib import Path

from typing_batch import cohort_manifest, partition_articles
from typing_cost import DEFAULT_DB, ROOT, sha256, write_json


def load_script(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


project_builder = load_script("project_unigram_builder", "build-project-unigram.py")
blend_builder = load_script("unigram_blend_builder", "build-unigram-blend.py")
model_builder = load_script("project_unigram_model_builder", "benchmark-project-unigram.py")
iterative_builder = load_script("iterative_unigram_builder", "build-iterative-unigram.py")
CONFIG = ROOT / "maintained-unigram.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference-db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--config", type=Path, default=CONFIG)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        if args.output.exists() and any(args.output.iterdir()):
            raise ValueError("Refuse to overwrite a nonempty maintained-model directory")
        args.output.mkdir(parents=True, exist_ok=True)
        split = config["partition"]
        if split["validation_articles"] != split["final_test_articles"]:
            raise ValueError("The maintained builder requires equal validation and final-test cohorts")
        _, partition = partition_articles(
            split["seed"], split["training_articles"], split["validation_articles"],
            args.output / "partition.json")
        for name in ("training", "validation", "test"):
            write_json(args.output / f"{name}.json", cohort_manifest(partition, name))
        count_config = config["counts"]
        project_counts = args.output / "project-occurrence.occ"
        project_report = project_builder.build(
            args.output / "training.json", project_counts, "occurrence", count_config["floor"], True)
        iterative = count_config["method"].startswith("iterative ")
        initial_counts = (args.output / "project-unigram-v1-initial.occ"
                          if iterative else args.output / f"{config['version']}.occ")
        blend_report = blend_builder.build(
            project_counts, initial_counts, count_config["project_weight"], count_config["integer_scale"])
        iterative_report = None
        if iterative:
            selected_counts = args.output / f"{config['version']}.occ"
            iterative_report = iterative_builder.build(
                args.output / "training.json", initial_counts, selected_counts,
                count_config["floor"], count_config["max_iterations"],
                iterative_builder.BASE_COUNTS, count_config["project_weight"],
                count_config["integer_scale"])
        else:
            selected_counts = initial_counts
        database = args.output / f"{config['version']}.db"
        model_report = model_builder.build_model(
            args.reference_db, selected_counts, project_counts.with_suffix(".corpus.txt"), database, True)
        manifest = {
            "version": config["version"],
            "configuration": str(args.config),
            "configuration_sha256": sha256(args.config),
            "reference_database": str(args.reference_db),
            "reference_database_sha256": sha256(args.reference_db),
            "partition": partition,
            "project_counts": project_report,
            "blend": blend_report,
            "iterative_segmentation": iterative_report,
            "model": model_report,
            "output_database": str(database),
            "output_database_sha256": sha256(database),
            "independence": "Only the 800 training articles enter unigram counts and paired bigrams.",
        }
        write_json(args.output / "manifest.json", manifest)
        print(json.dumps({
            "version": config["version"],
            "database": str(database),
            "database_sha256": manifest["output_database_sha256"],
            "training_articles": split["training_articles"],
        }, ensure_ascii=False, indent=2))
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    main()
