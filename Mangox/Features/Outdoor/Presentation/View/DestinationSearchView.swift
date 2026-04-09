import SwiftUI
import MapKit
import CoreLocation

// MARK: - Stable ID for MKLocalSearchCompletion

extension MKLocalSearchCompletion {
    /// Composite ID combining title + subtitle to disambiguate results with the same
    /// street name in different cities (e.g. "Calle Hidalgo 1" in Querétaro vs CDMX).
    var stableID: String { "\(title)|\(subtitle)" }
}

// MARK: - Search region bias (MapKit relevance)

/// Controls how large the `MKCoordinateRegion` around the user is when querying
/// `MKLocalSearchCompleter`. Wider regions let MapKit return more distant matches;
/// **regional** bias (rough location) avoids the old 24° “half the planet” window
/// that surfaced unrelated countries when GPS wasn’t marked “precise” yet.
enum DestinationSearchMapBias: Equatable {
    /// Live GPS fix — neighborhood-sized region.
    case preciseGPS
    /// Last rough fix / cached bias — state/country scale, still anchored on the user.
    case regional
    /// No location yet — fallback coordinate only; modest wide span (not global).
    case wideFallback
}

// MARK: - MKLocalSearchCompleter wrapper (typeahead-optimised)

/// Lightweight typeahead search backed by `MKLocalSearchCompleter`.
///
/// Unlike `MKLocalSearch`, the completer is specifically designed for real-time
/// search-as-you-type: it caches locally, throttles network hits internally,
/// and returns completions almost instantly — removing the need for manual
/// debouncing and eliminating the latency that causes keyboard lag.
@Observable
@MainActor
final class DestinationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []
    var isSearching: Bool = false

    // Lazy so MKLocalSearchCompleter is only created on first use, not at @State init time.
    // This keeps OutdoorDashboardView creation (during the push animation) free of MapKit work.
    private var _completer: MKLocalSearchCompleter?
    private var completer: MKLocalSearchCompleter {
        if let c = _completer { return c }
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.resultTypes = [.address, .pointOfInterest]
        _completer = c
        return c
    }

    override init() {
        super.init()
        // Intentionally empty — MKLocalSearchCompleter created on first use.
    }

    /// Eagerly create the MKLocalSearchCompleter to pre-warm MapKit search infrastructure.
    /// Call this after the navigation push animation completes (≥350ms after appear).
    func warmUp() {
        _ = completer  // triggers lazy init
    }

    /// Update the query fragment and search region.
    /// - `bias`: **preciseGPS** = city/neighborhood; **regional** = state/country around any rough fix;
    ///   **wideFallback** = only when no real location exists (still much smaller than the previous 24° global window).
    func update(query: String, near coordinate: CLLocationCoordinate2D, bias: DestinationSearchMapBias) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completer.cancel()
            completions = []
            isSearching = false
            return
        }
        let span: MKCoordinateSpan
        switch bias {
        case .preciseGPS:
            span = MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        case .regional:
            // ~300–400 km — keeps results in the user’s country/region without global POI competition.
            span = MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
        case .wideFallback:
            // Large but not planetary; reduces “random country” matches vs the old 24° × 24° default.
            span = MKCoordinateSpan(latitudeDelta: 9.0, longitudeDelta: 9.0)
        }
        completer.region = MKCoordinateRegion(center: coordinate, span: span)
        isSearching = true
        completer.queryFragment = trimmed
    }

    func cancel() {
        _completer?.cancel()
        completions = []
        isSearching = false
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }

    /// Resolve a completion into a full `MKMapItem` (one lightweight network hit on tap).
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first
        } catch {
            return nil
        }
    }
}

// MARK: - Shared Search Results List

/// Reusable search results list used by both the full-screen overlay and the sheet-based search page.
/// Extracted to eliminate ~90 lines of duplication and ensure consistent behavior.
struct SearchResultsList: View {
    var completions: [MKLocalSearchCompletion]
    var isSearching: Bool
    var resolvingIndex: Int?
    var onSelect: (MKLocalSearchCompletion, Int) -> Void

    var body: some View {
        if isSearching && completions.isEmpty {
            ProgressView()
                .tint(AppColor.mango)
                .padding(.top, 32)
            Spacer(minLength: 0)
        } else if !completions.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Use title+subtitle as stable ID — MKLocalSearchCompletion has no UUID,
                    // and \.offset causes full list rebuilds whenever results update.
                    // Title alone is not unique (e.g. "Hidalgo" appears in many cities),
                    // so we combine title+subtitle to disambiguate.
                    ForEach(Array(completions.enumerated()), id: \.element.stableID) { idx, item in
                        Button {
                            onSelect(item, idx)
                        } label: {
                            HStack(spacing: 10) {
                                if resolvingIndex == idx {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(AppColor.mango)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(AppColor.mango.opacity(0.8))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.45))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(resolvingIndex != nil)
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared Search State Hook

/// Manages debounced search updates and resolve-and-select logic.
/// Reused by both overlay and sheet wrappers.
private func makeSearchOnChange(
    query: String,
    completer: DestinationSearchCompleter,
    searchBiasCoordinate: CLLocationCoordinate2D,
    mapBias: DestinationSearchMapBias,
    debounceTask: inout Task<Void, Never>?
) {
    debounceTask?.cancel()
    debounceTask = Task {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        completer.update(
            query: query,
            near: searchBiasCoordinate,
            bias: mapBias
        )
    }
}

// MARK: - Extracted Destination Search Overlay

/// Full-screen destination search extracted from OutdoorDashboardView.
///
/// By living in its own View struct, `searchQuery` changes only invalidate
/// this subtree — not the entire 3 000-line dashboard body. This is the
/// single biggest fix for the keyboard / typing lag.
struct DestinationSearchOverlay: View {
    /// Pre-initialized completer passed from the parent so MapKit search infra is already warm.
    var completer: DestinationSearchCompleter
    /// Called when the user picks a destination. Passes the resolved `MKMapItem`.
    var onSelect: (MKMapItem) -> Void
    /// Called when the user taps back / dismisses.
    var onDismiss: () -> Void
    /// How strongly to anchor autocomplete around `searchBiasCoordinate` (see `DestinationSearchMapBias`).
    var searchMapBias: DestinationSearchMapBias
    /// Center for `MKLocalSearchCompleter.region` — GPS fix, last rough fix, or neutral fallback.
    var searchBiasCoordinate: CLLocationCoordinate2D

    // All search state is LOCAL to this view — no parent re-renders on keystroke.
    @State private var searchQuery = ""
    @FocusState private var focused: Bool
    @State private var resolvingIndex: Int? = nil
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var resolveErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())

                Text("Choose Destination")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
                TextField("Search destination…", text: $searchQuery)
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { focused = false }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        completer.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            // Results (shared component)
            if !completer.completions.isEmpty || (completer.isSearching && completer.completions.isEmpty) {
                SearchResultsList(
                    completions: completer.completions,
                    isSearching: completer.isSearching,
                    resolvingIndex: resolvingIndex,
                    onSelect: { item, idx in resolveAndSelect(item, at: idx) }
                )
            } else if !searchQuery.isEmpty && !completer.isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No results found")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 48)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.bg.ignoresSafeArea())
        .onChange(of: searchQuery) {
            makeSearchOnChange(
                query: searchQuery,
                completer: completer,
                searchBiasCoordinate: searchBiasCoordinate,
                mapBias: searchMapBias,
                debounceTask: &searchDebounceTask
            )
        }
        .onAppear {
            // Clear any stale results from a previous session.
            completer.cancel()
            searchQuery = ""
            resolvingIndex = nil
            // Focus immediately — no artificial delay needed since the completer
            // was pre-initialized by the parent before this overlay was shown.
            focused = true
        }
        .onChange(of: searchMapBias) { _, newBias in
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else { return }
            completer.update(query: q, near: searchBiasCoordinate, bias: newBias)
        }
        .alert("Couldn’t open destination", isPresented: Binding(
            get: { resolveErrorMessage != nil },
            set: { if !$0 { resolveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { resolveErrorMessage = nil }
        } message: {
            Text(resolveErrorMessage ?? "Try selecting the destination again.")
        }
    }

    private func resolveAndSelect(_ completion: MKLocalSearchCompletion, at index: Int) {
        focused = false
        resolvingIndex = index
        Task {
            if let mapItem = await completer.resolve(completion) {
                onSelect(mapItem)
            } else {
                resolveErrorMessage = "We couldn’t load that result right now. Check your connection and try again."
            }
            resolvingIndex = nil
        }
    }
}

// MARK: - Extracted Route Search Page (sheet version)

/// Search page used inside the route selection sheet.
/// Shares SearchResultsList with DestinationSearchOverlay for consistency.
struct RouteSearchPage: View {
    /// Shared with `OutdoorDashboardView` so MapKit search infra is already warm.
    var completer: DestinationSearchCompleter
    var onSelect: (MKMapItem) -> Void
    var onBack: () -> Void
    var searchBiasCoordinate: CLLocationCoordinate2D
    var searchMapBias: DestinationSearchMapBias

    @State private var searchQuery = ""
    @FocusState private var focused: Bool
    @State private var resolvingIndex: Int? = nil
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var resolveErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.45))
                TextField("Search destination", text: $searchQuery)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { focused = false }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Results (shared component)
            if !completer.completions.isEmpty || (completer.isSearching && completer.completions.isEmpty) {
                SearchResultsList(
                    completions: completer.completions,
                    isSearching: completer.isSearching,
                    resolvingIndex: resolvingIndex,
                    onSelect: { item, idx in resolveAndSelect(item, at: idx) }
                )
            } else if completer.completions.isEmpty && !searchQuery.isEmpty && !completer.isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("No results")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 48)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .navigationTitle("Navigate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .foregroundStyle(AppColor.mango)
            }
        }
        .onChange(of: searchQuery) {
            makeSearchOnChange(
                query: searchQuery,
                completer: completer,
                searchBiasCoordinate: searchBiasCoordinate,
                mapBias: searchMapBias,
                debounceTask: &searchDebounceTask
            )
        }
        .onAppear {
            // Clear stale state from any previous search session.
            completer.cancel()
            searchQuery = ""
            resolvingIndex = nil
            // By the time the sheet opens, MapKit is already warm from the outdoor screen
            // pre-warm, so keyboard focus is immediate.
            focused = true
        }
        .onChange(of: searchMapBias) { _, newBias in
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else { return }
            completer.update(query: q, near: searchBiasCoordinate, bias: newBias)
        }
        .alert("Couldn’t open destination", isPresented: Binding(
            get: { resolveErrorMessage != nil },
            set: { if !$0 { resolveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { resolveErrorMessage = nil }
        } message: {
            Text(resolveErrorMessage ?? "Try selecting the destination again.")
        }
    }

    private func resolveAndSelect(_ completion: MKLocalSearchCompletion, at index: Int) {
        focused = false
        resolvingIndex = index
        Task {
            if let mapItem = await completer.resolve(completion) {
                onSelect(mapItem)
            } else {
                resolveErrorMessage = "We couldn’t load that result right now. Check your connection and try again."
            }
            resolvingIndex = nil
        }
    }
}
