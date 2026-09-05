#!/usr/bin/env python3
"""Build the small, auditable legal corpus pack consumed by AMT.

The source dataset is intentionally kept outside the AMT repository. This
exporter selects structured records and exact source evidence, excludes PDF
files, and writes deterministic JSON plus a Float16 embedding matrix.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import unicodedata
from pathlib import Path
from typing import Any, Iterable


DATASET_REVISION = "17a6fe91aad1b9451ecfa49d086ad086c44e6120"
EMBEDDING_MODEL = "intfloat/multilingual-e5-small"
EMBEDDING_REVISION = "614241f622f53c4eeff9890bdc4f31cfecc418b3"
EMBEDDING_DIMENSION = 384
DATASET_VIEW_LABELS = {
    "hukumonline": "hukumonline-kamus",
    "combined": "hukumonline-kamus-combined",
    "combined-deduplicated": "hukumonline-kamus-combined-deduplicated",
    "dictionary-serving": "hukumonline-kamus-dictionary-serving",
}
DATASET_VIEW_ALIASES = {"dictionary-primary": "dictionary-serving"}
ACTIONABLE_VERIFICATION_STATUSES = {
    "machine_exact_unreviewed",
    "machine_ocr_tolerant_unreviewed",
    "human_verified",
}
DICTIONARY_EVIDENCE_LINK_TYPES = {
    "normalized_exact_text",
    "local_passage_ocr_tolerant",
}


def canonical_dataset_view(dataset_view: str) -> str:
    return DATASET_VIEW_ALIASES.get(dataset_view, dataset_view)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def dump_json(path: Path, value: Any) -> None:
    payload = (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    atomic_replace(path, payload)


def atomic_replace(path: Path, content: bytes) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(content)
    temporary.replace(path)


def reference_summary(
    reference: dict[str, Any],
    regulation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    regulation = regulation or {}
    return {
        "reference_id": reference.get("reference_id", ""),
        "display_name": reference.get("display_name", ""),
        "official_detail_url": reference.get("official_detail_url")
        or regulation.get("official_detail_url"),
        "official_document_url": reference.get("official_document_url")
        or regulation.get("official_document_url"),
        "official_title": reference.get("official_title")
        or regulation.get("official_title")
        or "",
        "official_status": reference.get("official_status")
        or regulation.get("official_status_raw")
        or "",
        "official_status_code": reference.get("official_status_code")
        or regulation.get("official_status_code")
        or "",
    }


def source_evidence(
    link: dict[str, Any],
    passage: dict[str, Any],
    regulation: dict[str, Any],
) -> dict[str, Any]:
    evidence = {
        "passage_id": link["passage_id"],
        "reference_id": link["reference_id"],
        "article_locator": passage.get("article_number") or link.get("article_locator"),
        "page_start": link.get("evidence_page_start") or passage.get("pdf_page_start"),
        "page_end": link.get("evidence_page_end") or passage.get("pdf_page_end"),
        "matched_definition_text": link.get("matched_definition_text", ""),
        "official_detail_url": regulation.get("official_detail_url"),
        "official_document_url": regulation.get("official_document_url"),
        "regulation_title": regulation.get("official_title") or "",
        "verification_status": link.get("verification_status") or "",
    }
    for key in ("evidence_id", "edge_id", "match_method"):
        if link.get(key):
            evidence[key] = link[key]
    return evidence


def dictionary_evidence_link(evidence: dict[str, Any]) -> dict[str, Any]:
    """Adapt a serving-view evidence row to the exporter link shape."""
    match_method = evidence.get("match_method")
    return {
        "definition_passage_link_id": evidence.get("evidence_id")
        or evidence.get("passage_id"),
        "passage_id": evidence.get("passage_id"),
        "reference_id": evidence.get("regulation_id"),
        "article_locator": evidence.get("article_locator"),
        "evidence_page_start": evidence.get("page_start"),
        "evidence_page_end": evidence.get("page_end"),
        "matched_definition_text": evidence.get("matched_definition_text"),
        "verification_status": evidence.get("verification_status"),
        "match_method": match_method,
        "link_type": (
            "normalized_exact_text"
            if match_method == "nfkc_casefold_punctuation_insensitive_substring"
            else "local_passage_ocr_tolerant"
        ),
        "evidence_id": evidence.get("evidence_id"),
        "edge_id": evidence.get("edge_id"),
    }


def is_actionable(
    link: dict[str, Any],
    passage: dict[str, Any] | None,
    regulation: dict[str, Any] | None,
    document: dict[str, Any] | None,
) -> bool:
    if passage is None or regulation is None or document is None:
        return False
    if link.get("link_type") not in DICTIONARY_EVIDENCE_LINK_TYPES:
        return False
    if link.get("verification_status") not in ACTIONABLE_VERIFICATION_STATUSES:
        return False
    if regulation.get("official_status_code") != "in_force":
        return False
    if not regulation.get("official_detail_url"):
        return False
    if not regulation.get("official_document_url"):
        return False
    if document.get("download_status") != "success":
        return False
    if document.get("requires_ocr") is not False:
        return False
    if document.get("text_extraction_status") != "success":
        return False
    if not link.get("matched_definition_text"):
        return False
    return bool(passage.get("text_clean", "").strip())


def definition_source_record_ids(definition: dict[str, Any]) -> list[str]:
    source_records = definition.get("source_records")
    if isinstance(source_records, list):
        record_ids = [
            str(row.get("record_id"))
            for row in source_records
            if isinstance(row, dict) and row.get("record_id")
        ]
        if record_ids:
            return sorted(set(record_ids))

    source_record_id = definition.get("source_record_id")
    if source_record_id:
        return [str(source_record_id)]
    return [str(definition["record_id"])]


def embedding_lookup_key(row: dict[str, Any]) -> tuple[str, str]:
    """Build a stable text key for reusing an equivalent embedding row."""
    def normalize(value: Any) -> str:
        text = unicodedata.normalize("NFKC", str(value or ""))
        return re.sub(r"\s+", " ", text).strip().casefold()

    return normalize(row.get("term")), normalize(row.get("definition"))


def dictionary_primary_definitions(
    primary_rows: list[dict[str, Any]],
    definition_rows: list[dict[str, Any]],
    regulation_by_id: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    """Convert one primary projection row into one AMT concept row.

    ``dictionary-serving`` is deliberately the only serving input here. A
    term with an ambiguous or missing primary selection is omitted from the
    runtime dictionary rather than silently falling back to an alternative.
    The complete alternatives remain available in the dataset bundle.
    """
    definitions_by_id = {
        str(row.get("definition_id")): row
        for row in definition_rows
        if row.get("definition_id")
    }
    concepts: list[dict[str, Any]] = []
    for primary in primary_rows:
        if not primary.get("primary_available"):
            continue
        primary_definition_id = str(primary.get("primary_definition_id") or "")
        source_definition = definitions_by_id.get(primary_definition_id)
        if source_definition is None:
            raise ValueError(
                "dictionary_primary references missing definition "
                + primary_definition_id
            )

        references: list[dict[str, Any]] = []
        for reference_id in primary.get("primary_reference_ids") or []:
            reference_id = str(reference_id)
            regulation = regulation_by_id.get(reference_id)
            if regulation is None:
                raise ValueError(
                    "dictionary_primary references missing regulation "
                    + reference_id
                )
            references.append(
                {
                    "reference_id": reference_id,
                    "display_name": regulation.get("reference_name", ""),
                    "official_detail_url": regulation.get("official_detail_url"),
                    "official_document_url": regulation.get("official_document_url"),
                    "official_title": regulation.get("official_title", ""),
                    "official_status": regulation.get("official_status_raw", ""),
                    "official_status_code": regulation.get("official_status_code", ""),
                }
            )

        source_url = primary.get("primary_source_url")
        return_row = {
            # The term group is the runtime identity.  This prevents multiple
            # source definitions for the same term from becoming search hits.
            "record_id": primary["term_group_id"],
            "term_id": primary["term_group_id"],
            "term": primary.get("term", source_definition.get("term", "")),
            "definition": primary.get(
                "primary_definition",
                source_definition.get("definition", ""),
            ),
            "definition_index": source_definition.get("definition_index", 1),
            "references": references,
            "sources": [primary["primary_source"]]
            if primary.get("primary_source")
            else [],
            "source_urls": [source_url] if source_url else [],
            "_primary_evidence": primary.get("primary_evidence") or [],
            "_primary_is_actionable": bool(primary.get("primary_is_actionable")),
        }
        concepts.append(return_row)

    return concepts


def build_pack(
    source_root: Path,
    output_root: Path,
    dataset_view: str = "hukumonline",
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    dataset_view = canonical_dataset_view(dataset_view)
    if dataset_view not in DATASET_VIEW_LABELS:
        raise ValueError(f"Unsupported dataset view: {dataset_view}")

    data_root = source_root / "hukumonline_kamus_hf" / "data"
    full_root = source_root / "hukumonline_kamus_hf" / "stage_4_6_full"
    full_data = full_root / "data"

    if dataset_view == "hukumonline":
        definitions_filename = "definitions.jsonl"
        regulations_filename = "regulations.jsonl"
        relations_filename = "regulation_relations.jsonl"
    elif dataset_view == "combined":
        definitions_filename = "combined_definitions.jsonl"
        regulations_filename = "combined_regulations.jsonl"
        relations_filename = "combined_regulation_relations.jsonl"
    elif dataset_view == "dictionary-serving":
        definitions_filename = "dictionary_primary.jsonl"
        regulations_filename = "dictionary_regulations.jsonl"
        relations_filename = "dictionary_regulation_relations.jsonl"
    else:
        definitions_filename = "combined_definitions_deduplicated.jsonl"
        regulations_filename = "combined_regulations.jsonl"
        relations_filename = "combined_regulation_relations.jsonl"

    definitions_path = data_root / definitions_filename
    regulations_path = data_root / regulations_filename
    relations_path = data_root / relations_filename
    dictionary_definitions_path = data_root / "dictionary_definitions.jsonl"
    dictionary_primary_path = data_root / "dictionary_primary.jsonl"
    dictionary_terms_path = data_root / "dictionary_terms.jsonl"
    dictionary_alternatives_path = data_root / "dictionary_alternatives.jsonl"
    links_path = full_data / "definition_passage_links.jsonl"
    passages_path = full_data / "regulation_passages.jsonl"
    documents_path = full_data / "regulation_documents.jsonl"

    required = [
        definitions_path,
        regulations_path,
        relations_path,
        links_path,
        passages_path,
        documents_path,
    ]
    if dataset_view == "dictionary-serving":
        required.extend(
            [
                dictionary_definitions_path,
                dictionary_primary_path,
                dictionary_terms_path,
                dictionary_alternatives_path,
            ]
        )
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing corpus inputs: " + ", ".join(missing))

    definitions = read_jsonl(definitions_path)
    regulations = read_jsonl(regulations_path)
    relations = read_jsonl(relations_path)
    dictionary_primary_rows: list[dict[str, Any]] = []
    dictionary_term_rows: list[dict[str, Any]] = []
    dictionary_alternative_rows: list[dict[str, Any]] = []
    links = read_jsonl(links_path)
    passages = {row["passage_id"]: row for row in read_jsonl(passages_path)}
    documents = {row["document_id"]: row for row in read_jsonl(documents_path)}
    regulation_by_id = {row["reference_id"]: row for row in regulations}
    if dataset_view == "dictionary-serving":
        dictionary_primary_rows = read_jsonl(dictionary_primary_path)
        dictionary_term_rows = read_jsonl(dictionary_terms_path)
        dictionary_alternative_rows = read_jsonl(dictionary_alternatives_path)
        definitions = dictionary_primary_definitions(
            dictionary_primary_rows,
            read_jsonl(dictionary_definitions_path),
            regulation_by_id,
        )
    links_by_record: dict[str, list[dict[str, Any]]] = {}
    if dataset_view != "dictionary-serving":
        for link in links:
            links_by_record.setdefault(link["record_id"], []).append(link)

    source_passages: dict[str, dict[str, Any]] = {}
    concepts: list[dict[str, Any]] = []
    for definition in sorted(definitions, key=lambda row: row["record_id"]):
        evidences: list[dict[str, Any]] = []
        actionable_evidences: list[dict[str, Any]] = []
        if dataset_view == "dictionary-serving":
            source_links = [
                dictionary_evidence_link(evidence)
                for evidence in definition.get("_primary_evidence") or []
                if evidence.get("passage_id") and evidence.get("regulation_id")
            ]
        else:
            source_links = [
                link
                for source_record_id in definition_source_record_ids(definition)
                for link in links_by_record.get(source_record_id, [])
            ]
        if dataset_view == "dictionary-serving":
            # Preserve the serving view's evidence order. It is meaningful
            # for deterministic primary evidence selection when a definition
            # has more than one official passage edge.
            seen_link_ids: set[str] = set()
            unique_links: list[dict[str, Any]] = []
            for link in source_links:
                link_id = str(
                    link.get("definition_passage_link_id") or link.get("passage_id")
                )
                if link_id in seen_link_ids:
                    continue
                seen_link_ids.add(link_id)
                unique_links.append(link)
        else:
            unique_links = sorted(
                {
                    str(link.get("definition_passage_link_id") or link.get("passage_id")): link
                    for link in source_links
                }.values(),
                key=lambda row: (
                    row["passage_id"],
                    row.get("definition_passage_link_id", ""),
                ),
            )
        for link in unique_links:
            # The dictionary serving view carries both exact and OCR-tolerant
            # evidence. The latter remains explicitly labelled as unreviewed.
            if (
                dataset_view != "dictionary-serving"
                and link.get("link_type") != "normalized_exact_text"
            ):
                continue
            passage = passages.get(link["passage_id"])
            regulation = regulation_by_id.get(link["reference_id"])
            document = documents.get(passage.get("document_id")) if passage else None
            if passage is None or regulation is None:
                continue
            evidence = source_evidence(link, passage, regulation)
            evidences.append(evidence)
            serving_evidence_is_actionable = (
                dataset_view == "dictionary-serving"
                and definition.get("_primary_is_actionable") is True
                and regulation.get("official_status_code") == "in_force"
                and regulation.get("official_detail_url")
                and regulation.get("official_document_url")
            )
            if (
                serving_evidence_is_actionable
                or (
                    dataset_view != "dictionary-serving"
                    and is_actionable(link, passage, regulation, document)
                )
            ):
                actionable_evidences.append(evidence)
            source_passage_id = link["passage_id"]
            source_passages.setdefault(
                source_passage_id,
                {
                    "passage_id": source_passage_id,
                    "reference_id": link["reference_id"],
                    "article_locator": (
                        passage.get("article_number")
                        if dataset_view == "dictionary-serving"
                        else passage.get("article_number") or link.get("article_locator")
                    ),
                    "page_start": passage.get("pdf_page_start"),
                    "page_end": passage.get("pdf_page_end"),
                    "text": passage.get("text_clean")
                    or passage.get("text_raw", ""),
                    "official_document_url": regulation.get("official_document_url"),
                    "concept_ids": [],
                },
            )
            if definition["record_id"] not in source_passages[source_passage_id]["concept_ids"]:
                source_passages[source_passage_id]["concept_ids"].append(definition["record_id"])

        concepts.append(
            {
                "record_id": definition["record_id"],
                "term_id": definition.get("term_id", ""),
                "term": definition.get("term", ""),
                "definition": definition.get("definition", ""),
                "definition_index": definition.get("definition_index", 1),
                "references": [
                    reference_summary(
                        row,
                        regulation_by_id.get(row.get("reference_id")),
                    )
                    for row in sorted(
                        definition.get("references", []),
                        key=lambda row: row.get("reference_id", ""),
                    )
                ],
                "evidence": evidences,
                "actionable": bool(actionable_evidences),
                "actionable_evidence": actionable_evidences[0] if actionable_evidences else None,
                "sources": sorted(
                    {
                        str(source)
                        for source in (
                            definition.get("sources")
                            or [
                                record.get("source")
                                for record in definition.get("source_records", [])
                                if isinstance(record, dict)
                            ]
                        )
                        if str(source).strip()
                    }
                ),
                "source_urls": sorted(
                    {
                        str(source_url)
                        for source_url in (
                            definition.get("source_urls")
                            or [definition.get("source_url", "")]
                        )
                        if str(source_url).strip()
                    }
                ),
            }
        )

    if dataset_view == "dictionary-serving":
        # Alternatives are not search concepts, but their official passage
        # evidence must remain available for the contextual provenance UI.
        # They intentionally do not add a primary concept ID to the passage.
        for alternative in dictionary_alternative_rows:
            for raw_evidence in alternative.get("evidence") or []:
                link = dictionary_evidence_link(raw_evidence)
                passage = passages.get(link.get("passage_id"))
                regulation = regulation_by_id.get(link.get("reference_id"))
                if passage is None or regulation is None:
                    continue
                source_passages.setdefault(
                    link["passage_id"],
                    {
                        "passage_id": link["passage_id"],
                        "reference_id": link["reference_id"],
                        "article_locator": passage.get("article_number"),
                        "page_start": passage.get("pdf_page_start"),
                        "page_end": passage.get("pdf_page_end"),
                        "text": passage.get("text_clean")
                        or passage.get("text_raw", ""),
                        "official_document_url": regulation.get(
                            "official_document_url"
                        ),
                        "concept_ids": [],
                    },
                )

    selected_regulations = []
    if dataset_view == "dictionary-serving":
        # The serving regulation view is itself the curated provenance
        # boundary. Keep every node in that view so alternatives can resolve
        # their source context even when a node is not referenced by a primary
        # search result.
        used_reference_ids = set(regulation_by_id)
    else:
        used_reference_ids = {
            evidence["reference_id"]
            for concept in concepts
            for evidence in concept["evidence"]
        }
        used_reference_ids.update(
            reference["reference_id"]
            for concept in concepts
            for reference in concept["references"]
            if reference.get("reference_id") in regulation_by_id
        )

    # Relations are useful for a regulation already represented by evidence,
    # but they must never introduce a dangling foreign key. Include a related
    # regulation when its structured record exists, then retain only complete
    # relation pairs in the exported pack. Unresolved upstream claims remain
    # outside the runtime pack instead of making the whole corpus unloadable.
    related_reference_ids = {
        endpoint
        for row in relations
        if row.get("source_reference_id") in used_reference_ids
        or row.get("target_reference_id") in used_reference_ids
        for endpoint in (
            row.get("source_reference_id"),
            row.get("target_reference_id"),
        )
        if endpoint in regulation_by_id
    }
    used_reference_ids.update(related_reference_ids)
    for regulation in sorted(regulations, key=lambda row: row["reference_id"]):
        if regulation["reference_id"] not in used_reference_ids:
            continue
        selected_regulations.append(
            {
                "reference_id": regulation["reference_id"],
                "reference_name": regulation.get("reference_name", ""),
                "citation_normalized": regulation.get("citation_normalized", ""),
                "official_detail_url": regulation.get("official_detail_url"),
                "official_document_url": regulation.get("official_document_url"),
                "official_title": regulation.get("official_title", ""),
                "official_status_raw": regulation.get("official_status_raw") or "",
                "official_status_code": regulation.get("official_status_code") or "",
                "institution": regulation.get("institution"),
                "number": regulation.get("number"),
                "year": regulation.get("year"),
            }
        )

    selected_regulation_ids = {row["reference_id"] for row in selected_regulations}
    selected_relations = [
        {
            "relation_id": row.get("relation_id", ""),
            "source_reference_id": row.get("source_reference_id", ""),
            "target_reference_id": row.get("target_reference_id", ""),
            "relation_type": row.get("relation_type", ""),
            "inverse_relation_type": row.get("inverse_relation_type", ""),
            "evidence_source": row.get("evidence_source", ""),
            "evidence_text": row.get("evidence_text", ""),
        }
        for row in sorted(relations, key=lambda row: row.get("relation_id", ""))
        if row.get("source_reference_id") in selected_regulation_ids
        and row.get("target_reference_id") in selected_regulation_ids
    ]

    inputs = {path.name: sha256(path) for path in required}
    concepts.sort(key=lambda row: row["record_id"])
    concept_order_sha256 = sha256_text(
        "\n".join(row["record_id"] for row in concepts)
    )
    dictionary_primary_rows.sort(key=lambda row: row.get("term_group_id", ""))
    dictionary_term_rows.sort(key=lambda row: row.get("term_group_id", ""))
    dictionary_alternative_rows.sort(
        key=lambda row: (
            row.get("term_group_id", ""),
            row.get("definition_id", ""),
        )
    )
    manifest = {
        "schema_version": "amt-legal-corpus-v2",
        "corpus_version": f"{DATASET_VIEW_LABELS[dataset_view]}@{DATASET_REVISION}",
        "source_dataset_revision": DATASET_REVISION,
        "source_dataset_view": dataset_view,
        "source_input_sha256": inputs,
        "concept_count": len(concepts),
        "regulation_count": len(selected_regulations),
        "relation_count": len(selected_relations),
        "source_passage_count": len(source_passages),
        "actionable_concept_count": sum(1 for concept in concepts if concept["actionable"]),
        "term_group_count": len(dictionary_term_rows),
        "alternative_count": len(dictionary_alternative_rows),
        "embedding": {
            "model": EMBEDDING_MODEL,
            "revision": EMBEDDING_REVISION,
            "dimension": EMBEDDING_DIMENSION,
            "dtype": "float16-little-endian",
            "normalized": True,
            "passage_format": "passage: {term}\\n{definition}",
            "query_prefix": "query: ",
            "concept_order_sha256": concept_order_sha256,
        },
        "retrieval": {
            "rrf_k": 60,
            "lexical_top_k": 100,
            "semantic_top_k": 100,
            "suggestion_candidate_limit": 3,
            "suggestion_minimum_span_tokens": 6,
            "suggestion_maximum_span_tokens": 80,
            "suggestion_minimum_keyword_coverage": 0.70,
            "suggestion_semantic_threshold": 0.60,
            "suggestion_top_one_margin": 0.03,
        },
        "files": {
            "concepts": "concepts.json",
            "regulations": "regulations.json",
            "relations": "relations.json",
            "source_passages": "source_passages.json",
            "embeddings": "definition_embeddings.f16",
            "dictionary_primary": "dictionary_primary.json",
            "dictionary_terms": "dictionary_terms.json",
            "dictionary_alternatives": "dictionary_alternatives.json",
        },
    }

    output_root.mkdir(parents=True, exist_ok=True)
    dump_json(output_root / "concepts.json", concepts)
    dump_json(output_root / "dictionary_primary.json", dictionary_primary_rows)
    dump_json(output_root / "dictionary_terms.json", dictionary_term_rows)
    dump_json(output_root / "dictionary_alternatives.json", dictionary_alternative_rows)
    dump_json(output_root / "regulations.json", selected_regulations)
    dump_json(output_root / "relations.json", selected_relations)
    for passage in source_passages.values():
        passage["concept_ids"] = sorted(set(passage["concept_ids"]))

    dump_json(
        output_root / "source_passages.json",
        sorted(source_passages.values(), key=lambda row: row["passage_id"]),
    )
    dump_json(output_root / "manifest.json", manifest)
    return concepts, manifest


def write_embeddings(concepts: list[dict[str, Any]], output_root: Path, model_name: str) -> None:
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError as error:
        raise RuntimeError("sentence-transformers is required to build embeddings") from error

    model = SentenceTransformer(model_name, revision=EMBEDDING_REVISION)
    texts = [f"passage: {row['term']}\n{row['definition']}" for row in concepts]
    vectors = model.encode(
        texts,
        batch_size=32,
        convert_to_numpy=True,
        normalize_embeddings=True,
        show_progress_bar=True,
    )
    if vectors.ndim != 2 or vectors.shape != (len(concepts), EMBEDDING_DIMENSION):
        raise ValueError(f"Unexpected embedding shape: {vectors.shape}")
    payload = b"".join(struct.pack("<e", float(value)) for row in vectors for value in row)
    atomic_replace(output_root / "definition_embeddings.f16", payload)


def write_reused_embeddings(
    concepts: list[dict[str, Any]],
    output_root: Path,
    source_root: Path,
) -> None:
    """Reuse pinned vectors when the new serving view has identical text.

    The primary projection changes row identity and order, but its selected
    definition text is already present in the previous combined pack. This
    lets a local migration avoid a model download while still proving every
    vector came from the same pinned E5 matrix.
    """
    source_concepts_path = source_root / "concepts.json"
    source_embeddings_path = source_root / "definition_embeddings.f16"
    if not source_concepts_path.is_file() or not source_embeddings_path.is_file():
        raise FileNotFoundError(
            "Embedding source must contain concepts.json and "
            "definition_embeddings.f16"
        )

    source_concepts = json.loads(source_concepts_path.read_text(encoding="utf-8"))
    if not isinstance(source_concepts, list):
        raise ValueError("Embedding source concepts.json must contain an array")
    source_payload = source_embeddings_path.read_bytes()
    expected_bytes = len(source_concepts) * EMBEDDING_DIMENSION * 2
    if len(source_payload) != expected_bytes:
        raise ValueError(
            "Embedding source has an unexpected byte count: "
            f"{len(source_payload)} != {expected_bytes}"
        )

    source_indexes: dict[tuple[str, str], int] = {}
    source_indexes_by_term: dict[str, list[int]] = {}
    for index, concept in enumerate(source_concepts):
        key = embedding_lookup_key(concept)
        if key in source_indexes:
            raise ValueError("Embedding source has duplicate text key: " + repr(key))
        source_indexes[key] = index
        source_indexes_by_term.setdefault(key[0], []).append(index)

    chunks: list[bytes] = []
    missing: list[str] = []
    row_bytes = EMBEDDING_DIMENSION * 2
    for concept in concepts:
        key = embedding_lookup_key(concept)
        source_index = source_indexes.get(key)
        if source_index is None:
            # Some source pages prepend the term to the definition or differ
            # only in OCR punctuation. Reuse a vector by term only when the
            # old pack has exactly one candidate; never guess among several
            # legal definitions with the same term.
            same_term = source_indexes_by_term.get(key[0], [])
            if len(same_term) == 1:
                source_index = same_term[0]
        if source_index is None:
            missing.append(str(concept.get("record_id")))
            continue
        start = source_index * row_bytes
        chunks.append(source_payload[start : start + row_bytes])
    if missing:
        sample = ", ".join(missing[:5])
        raise ValueError(
            f"{len(missing)} primary concepts have no reusable embedding; sample: {sample}"
        )
    atomic_replace(output_root / "definition_embeddings.f16", b"".join(chunks))


def finalize_manifest(manifest: dict[str, Any], output_root: Path) -> dict[str, Any]:
    files = manifest["files"]
    missing = [
        name for name in files.values()
        if not (output_root / name).is_file()
    ]
    if missing:
        raise FileNotFoundError(
            "Missing exported corpus files: " + ", ".join(missing)
        )
    manifest["files_sha256"] = {
        name: sha256(output_root / name)
        for name in files.values()
    }
    dump_json(output_root / "manifest.json", manifest)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--embedding-model", default=EMBEDDING_MODEL)
    parser.add_argument(
        "--dataset-view",
        choices=sorted(set(DATASET_VIEW_LABELS) | set(DATASET_VIEW_ALIASES)),
        default="hukumonline",
        help="Definition/reference view to export into the AMT pack.",
    )
    parser.add_argument("--skip-embeddings", action="store_true")
    parser.add_argument(
        "--reuse-embeddings-from",
        type=Path,
        help="Reuse vectors from another compatible AMT corpus pack by term+definition text.",
    )
    args = parser.parse_args()
    args.dataset_view = canonical_dataset_view(args.dataset_view)

    if args.skip_embeddings and args.reuse_embeddings_from:
        parser.error("--skip-embeddings and --reuse-embeddings-from are mutually exclusive")

    existing_manifest: dict[str, Any] | None = None
    if args.skip_embeddings:
        existing_manifest_path = args.output_root / "manifest.json"
        if existing_manifest_path.is_file():
            try:
                existing_manifest = json.loads(
                    existing_manifest_path.read_text(encoding="utf-8")
                )
            except json.JSONDecodeError as error:
                raise ValueError(
                    "--skip-embeddings membutuhkan manifest lama yang valid"
                ) from error

    concepts, manifest = build_pack(
        args.source_root,
        args.output_root,
        dataset_view=args.dataset_view,
    )
    if args.reuse_embeddings_from:
        write_reused_embeddings(
            concepts,
            args.output_root,
            args.reuse_embeddings_from,
        )
    elif not args.skip_embeddings:
        write_embeddings(concepts, args.output_root, args.embedding_model)
    else:
        # A skipped embedding build is valid only when the caller is reusing
        # an already generated matrix with the same source and concept order.
        if existing_manifest is None:
            raise FileNotFoundError(
                "--skip-embeddings requires the previous manifest.json"
            )
        if (
            existing_manifest.get("source_dataset_revision")
            != manifest["source_dataset_revision"]
            or existing_manifest.get("source_input_sha256")
            != manifest["source_input_sha256"]
        ):
            raise ValueError(
                "--skip-embeddings tidak boleh memakai embedding dari source corpus berbeda"
            )
        previous_embedding = existing_manifest.get("embedding", {})
        previous_order_hash = previous_embedding.get("concept_order_sha256")
        current_order_hash = manifest["embedding"]["concept_order_sha256"]
        if previous_order_hash is not None:
            if previous_order_hash != current_order_hash:
                raise ValueError(
                    "--skip-embeddings menemukan urutan konsep yang berbeda"
                )
        else:
            # Older packs predate the explicit order hash. Equal concept-file
            # hashes are sufficient to prove that their sorted record order
            # is unchanged before adding the stronger manifest field.
            previous_concepts_hash = existing_manifest.get(
                "files_sha256", {}
            ).get("concepts.json")
            current_concepts_hash = sha256(
                args.output_root / manifest["files"]["concepts"]
            )
            if previous_concepts_hash != current_concepts_hash:
                raise ValueError(
                    "--skip-embeddings tidak dapat membuktikan urutan konsep lama"
                )
        embedding_path = args.output_root / manifest["files"]["embeddings"]
        expected_bytes = len(concepts) * EMBEDDING_DIMENSION * 2
        if not embedding_path.is_file() or embedding_path.stat().st_size != expected_bytes:
            raise FileNotFoundError(
                "--skip-embeddings requires an existing embedding matrix with "
                "the expected concept count"
            )
    manifest = finalize_manifest(manifest, args.output_root)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
