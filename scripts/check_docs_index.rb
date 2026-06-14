#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).join("..").realpath
DOCS_DIR = ROOT.join("docs")
DOCS_INDEX = DOCS_DIR.join("README.md")
AGENTS_FILE = ROOT.join("AGENTS.md")

REQUIRED_AGENT_LINKS = %w[
  docs/README.md
  docs/agent-harness.md
  docs/architecture-map.md
  docs/validation.md
].freeze

def fail_with(message)
  warn(message)
  exit(1)
end

def ignored_by_git?(path)
  relative_path = path.relative_path_from(ROOT).to_s

  system("git", "-C", ROOT.to_s, "check-ignore", "--quiet", relative_path)
end

missing_required_files = [ DOCS_INDEX, AGENTS_FILE ].reject(&:file?)

if missing_required_files.any?
  fail_with(
    [
      "Missing required agent knowledge files:",
      *missing_required_files.map { |path| "- #{path.relative_path_from(ROOT)}" }
    ].join("\n")
  )
end

docs_index_text = DOCS_INDEX.read
agents_text = AGENTS_FILE.read

doc_paths = Dir.glob(DOCS_DIR.join("**/*.md").to_s).map do |filename|
  Pathname.new(filename)
end

markdown_docs = doc_paths.reject do |path|
  path.basename.to_s == "README.md" || ignored_by_git?(path)
end

markdown_docs = markdown_docs.map do |path|
  path.relative_path_from(DOCS_DIR).to_s
end.sort

linked_docs = docs_index_text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.filter_map do |target|
  target = target.split("#", 2).first
  next if target.start_with?("http://", "https://", "mailto:")

  Pathname.new(target).cleanpath.to_s.delete_prefix("./")
end

missing_index_links = markdown_docs - linked_docs

if missing_index_links.any?
  fail_with(
    [
      "docs/README.md is missing links for:",
      *missing_index_links.map { |path| "- docs/#{path}" }
    ].join("\n")
  )
end

missing_agent_links = REQUIRED_AGENT_LINKS.reject do |link|
  agents_text.include?(link)
end

if missing_agent_links.any?
  fail_with(
    [
      "AGENTS.md is missing required links:",
      *missing_agent_links.map { |path| "- #{path}" }
    ].join("\n")
  )
end

puts "Docs knowledge base check passed."
