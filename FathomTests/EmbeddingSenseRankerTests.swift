import Foundation
import Testing

@testable import Fathom

/// End-to-end quality gate for the on-device sense ranker: classic polysemy
/// cases must resolve to the right sense. Runs real Core ML inference against
/// the bundled model (hosted in the app, so `Bundle.main` has the resources).
struct EmbeddingSenseRankerTests {

    private static func sense(_ definition: String, examples: [String] = []) -> DictionarySense {
        DictionarySense(
            definition: definition, tags: nil, examples: examples.isEmpty ? nil : examples,
            quotes: nil, synonyms: nil, antonyms: nil, translations: nil, subsenses: nil
        )
    }

    private static func entry(word: String, _ senses: [(pos: String, senses: [DictionarySense])])
        -> DictionaryWordEntry
    {
        DictionaryWordEntry(
            word: word,
            entries: senses.map {
                DictionaryEntry(
                    language: DictionaryLanguage(code: "en", name: "English"),
                    partOfSpeech: $0.pos, pronunciations: nil, forms: nil,
                    senses: $0.senses, synonyms: nil, antonyms: nil
                )
            },
            source: nil
        )
    }

    private func rank(
        word: String, sentence: String, entry: DictionaryWordEntry, surfaceWord: String? = nil
    ) async -> RankedDefinition? {
        await EmbeddingSenseRanker.shared.rank(
            SenseRankingRequest(
                word: word, surfaceWord: surfaceWord ?? word, sentence: sentence, entry: entry))
    }

    // MARK: - Cases

    private static let bankEntry = entry(
        word: "bank",
        [
            (
                "noun",
                [
                    sense(
                        "a financial institution that accepts deposits and channels the money into lending activities",
                        examples: ["He cashed a check at the bank."]),
                    sense(
                        "sloping land, especially the slope beside a body of water",
                        examples: ["They pulled the canoe up on the bank."]),
                    sense("a long ridge or pile", examples: ["A huge bank of earth."]),
                ]
            ),
            (
                "verb",
                [
                    sense(
                        "to tip laterally while turning",
                        examples: ["The plane banked sharply to the left."])
                ]
            ),
        ]
    )

    @Test func riverBank() async throws {
        let ranked = try #require(
            await rank(
                word: "bank",
                sentence: "They had a picnic on the bank of the river, watching the water flow past.",
                entry: Self.bankEntry
            ))
        #expect(ranked.sense.definition.contains("sloping land"))
    }

    @Test func financialBank() async throws {
        let ranked = try #require(
            await rank(
                word: "bank",
                sentence: "The bank refused to extend the loan after reviewing her credit history.",
                entry: Self.bankEntry
            ))
        #expect(ranked.sense.definition.contains("financial institution"))
    }

    @Test func airplaneBanks() async throws {
        let ranked = try #require(
            await rank(
                word: "banked",
                sentence: "The aircraft banked steeply as it turned toward the runway.",
                entry: Self.bankEntry,
                surfaceWord: "banked"
            ))
        #expect(ranked.partOfSpeech == "verb")
    }

    @Test func cricketBatVsAnimal() async throws {
        let batEntry = Self.entry(
            word: "bat",
            [
                (
                    "noun",
                    [
                        Self.sense(
                            "a small nocturnal flying mammal that navigates by echolocation",
                            examples: ["Bats flew out of the cave at dusk."]),
                        Self.sense(
                            "a club made of wood used for hitting the ball in sports",
                            examples: ["She gripped the bat and waited for the pitch."]),
                    ]
                )
            ]
        )
        let ranked = try #require(
            await rank(
                word: "bat",
                sentence: "He swung the bat hard and sent the ball over the fence.",
                entry: batEntry
            ))
        #expect(ranked.sense.definition.contains("club"))
    }

    @Test func subsensesAreConsidered() async throws {
        let parent = DictionarySense(
            definition: "to move quickly on foot", tags: nil,
            examples: ["She runs every morning."], quotes: nil, synonyms: nil, antonyms: nil,
            translations: nil,
            subsenses: [
                Self.sense(
                    "of a machine or program: to operate or execute",
                    examples: ["The script runs on the server every night."])
            ]
        )
        let runEntry = DictionaryWordEntry(
            word: "run",
            entries: [
                DictionaryEntry(
                    language: DictionaryLanguage(code: "en", name: "English"),
                    partOfSpeech: "verb", pronunciations: nil, forms: nil,
                    senses: [parent], synonyms: nil, antonyms: nil
                )
            ],
            source: nil
        )
        let ranked = try #require(
            await rank(
                word: "run",
                sentence: "You can run the program from the terminal with a single command.",
                entry: runEntry
            ))
        #expect(ranked.sense.definition.contains("operate or execute"))
    }

    /// Real-world regression: the original ranker picked "That which confines
    /// or contracts" for a stomach cramp (word-echo gloss beating the true
    /// sense). Senses mirror the live Wiktionary entry.
    @Test func stomachCramp() async throws {
        let crampEntry = Self.entry(
            word: "cramp",
            [
                (
                    "noun",
                    [
                        Self.sense(
                            "A painful contraction of a muscle which cannot be controlled",
                            examples: ["He retired hurt at 31 due to a leg cramp."]),
                        Self.sense("That which confines or contracts."),
                        Self.sense("A clamp for carpentry or masonry."),
                    ]
                ),
                (
                    "verb",
                    [
                        Self.sense("(of a muscle) To contract painfully and uncontrollably."),
                        Self.sense("To prohibit movement or expression of.",
                            examples: ["You're cramping my style."]),
                        Self.sense("To fasten or hold with, or as if with, a cramp iron."),
                    ]
                ),
            ]
        )
        let ranked = try #require(
            await rank(
                word: "cramp",
                sentence: "Presently I was seized with a cramp in my stomach.",
                entry: crampEntry
            ))
        #expect(ranked.sense.definition.contains("painful contraction"))
    }

    @Test func latencyIsAcceptable() async throws {
        // Warm path budget: cached senses + one context embedding.
        _ = await rank(
            word: "bank",
            sentence: "She deposited the money at the bank on Tuesday.",
            entry: Self.bankEntry
        )
        let start = ContinuousClock.now
        _ = await rank(
            word: "bank",
            sentence: "Wild flowers grew all along the bank of the stream.",
            entry: Self.bankEntry
        )
        let elapsed = start.duration(to: .now)
        print("Warm re-rank latency: \(elapsed)")
        #expect(elapsed < .seconds(2))
    }

    @Test func modelCanDeallocateAndReload() async throws {
        await EmbeddingSenseRanker.shared.prewarm()
        await EmbeddingSenseRanker.shared.unload()
        
        let ranked = try #require(
            await rank(
                word: "bank",
                sentence: "They had a picnic on the bank of the river.",
                entry: Self.bankEntry
            )
        )
        #expect(ranked.sense.definition.contains("sloping land"))
    }

    @Test func confidenceRatioCheck() async throws {
        let entry = Self.entry(
            word: "ratioTest",
            [
                (
                    "noun",
                    [
                        Self.sense("First primary meaning that fits the context"),
                        Self.sense("Second meaning that is completely different"),
                        Self.sense("Third meaning that is also completely different"),
                    ]
                )
            ]
        )
        
        let ranked = try #require(
            await rank(
                word: "ratioTest",
                sentence: "This matches the first primary meaning that fits the context.",
                entry: entry
            )
        )
        #expect(ranked.isHighConfidence == true)
    }

    @Test func lemmatizationFallbackOn404() async throws {
        let mockService = MockVocabularyService()
        let bankEntry = DictionaryWordEntry(
            word: "bank",
            entries: [
                DictionaryEntry(
                    language: DictionaryLanguage(code: "en", name: "English"),
                    partOfSpeech: "verb", pronunciations: nil, forms: nil,
                    senses: [
                        DictionarySense(
                            definition: "to roll or incline laterally", tags: nil,
                            examples: nil, quotes: nil, synonyms: nil, antonyms: nil,
                            translations: nil, subsenses: nil
                        )
                    ], synonyms: nil, antonyms: nil
                )
            ],
            source: nil
        )
        mockService.stubbedResponses["bank"] = .success(bankEntry)
        mockService.stubbedResponses["banked"] = .failure(VocabularyServiceError.notFound)
        
        let mockRepo = MockVocabularyRepository()
        
        let viewModel = await VocabularySheetViewModel(
            word: "banked",
            language: "en",
            service: mockService,
            repository: mockRepo
        )
        
        try await Task.sleep(for: .seconds(0.5))
        
        let entry = await viewModel.entry
        #expect(entry?.word == "bank")
        let suggested = await viewModel.suggestedRootWord
        #expect(suggested == "bank")
        let rel = await viewModel.rootWordRelationship
        #expect(rel == "Lemma form of")
    }

    @Test func alternativeSpellingRedirect() async throws {
        let mockService = MockVocabularyService()
        let draughtEntry = DictionaryWordEntry(
            word: "draught",
            entries: [
                DictionaryEntry(
                    language: DictionaryLanguage(code: "en", name: "English"),
                    partOfSpeech: "noun", pronunciations: nil, forms: nil,
                    senses: [
                        DictionarySense(
                            definition: "Alternative spelling of draft", tags: nil,
                            examples: nil, quotes: nil, synonyms: nil, antonyms: nil,
                            translations: nil, subsenses: nil
                        )
                    ], synonyms: nil, antonyms: nil
                )
            ],
            source: nil
        )
        mockService.stubbedResponses["draught"] = .success(draughtEntry)
        
        let mockRepo = MockVocabularyRepository()
        
        let viewModel = await VocabularySheetViewModel(
            word: "draught",
            language: "en",
            service: mockService,
            repository: mockRepo
        )
        
        try await Task.sleep(for: .seconds(0.5))
        
        let suggested = await viewModel.suggestedRootWord
        #expect(suggested == "draft")
        let rel = await viewModel.rootWordRelationship
        #expect(rel == "Alternative spelling/form of")
    }
}

// MARK: - Mocks for Testing

class MockVocabularyService: VocabularyService {
    var stubbedResponses: [String: Result<DictionaryWordEntry, VocabularyServiceError>] = [:]
    
    override func fetchWord(
        _ word: String, language: String = "en", includeTranslations: Bool = false
    ) async throws -> DictionaryWordEntry {
        if let result = stubbedResponses[word.lowercased()] {
            switch result {
            case .success(let entry):
                return entry
            case .failure(let error):
                throw error
            }
        }
        throw VocabularyServiceError.notFound
    }
}

actor MockVocabularyRepository: VocabularyRepository {
    func listSavedWords() async -> [SavedWord] { [] }
    func addSavedWord(_ word: SavedWord) async {}
    func updateSavedWord(_ word: SavedWord) async {}
    func removeSavedWord(id: UUID) async {}
    func getSavedWord(word: String, language: String) async -> SavedWord? { nil }
    func setPinnedAt(id: UUID, pinnedAt: Date?) async {}
}
