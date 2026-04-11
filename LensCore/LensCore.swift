// LensCore — shared framework; no SwiftUI imports permitted here.
//
// This file satisfies the framework build target.
// All substantive types live in subdirectories:
//   Models/      — SwiftData entities (Feed, FeedItem, Category, …)
//   Persistence/ — ModelContainer setup, App Group config
//   Feeds/       — Fetch pipeline, parsers, feed factory
//   Events/      — Event bus types and EventBus actor
//   Theme/       — ThemeEngine, CSS composition
//   Routing/     — DeepLinkRouter
//
// Populated starting in Phase 2.
import Foundation
