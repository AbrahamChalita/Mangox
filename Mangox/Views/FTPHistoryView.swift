import SwiftData
import SwiftUI

struct FTPHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var results: [FTPTestResult] = []
    @State private var showApplyConfirmation = false
    @State private var selectedResult: FTPTestResult?

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.06)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if results.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        FTPRefreshScope {
                            VStack(spacing: 10) {
                                currentFTPBanner
                                ForEach(results) { result in
                                    resultCard(result)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
        }
        .onAppear { loadHistory() }
        .alert("Apply FTP", isPresented: $showApplyConfirmation, presenting: selectedResult) { result in
            Button("Cancel", role: .cancel) { selectedResult = nil }
            Button("Apply") {
                PowerZone.setFTP(result.estimatedFTP)
                FTPTestHistory.markApplied(id: result.id)
                FitnessSettingsSnapshotRecorder.recordFromCurrentSettings(
                    source: "ftp_test_applied", modelContext: modelContext)
                loadHistory()
                selectedResult = nil
            }
        } message: { result in
            Text("Set your FTP to \(result.estimatedFTP) W?")
        }
    }

    private func loadHistory() {
        results = FTPTestHistory.load().sorted { $0.date > $1.date }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FTP History")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(results.count) test\(results.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
        )
    }

    // MARK: - Current FTP Banner

    private var currentFTPBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppColor.mango)
            Text("CURRENT FTP")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.2)
            Spacer()
            Text("\(PowerZone.ftp)")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("W")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Result Card

    private func resultCard(_ result: FTPTestResult) -> some View {
        let zone = PowerZone.zone(for: result.estimatedFTP)
        let isCurrent = result.estimatedFTP == PowerZone.ftp

        return VStack(alignment: .leading, spacing: 10) {
            // Date + applied badge
            HStack {
                Text(result.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                if result.applied {
                    Text("APPLIED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppColor.success)
                        .tracking(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.success.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(result.date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

            // Main FTP value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(result.estimatedFTP)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(zone.color)
                Text("W")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))

                Spacer()

                if !isCurrent {
                    Button {
                        selectedResult = result
                        showApplyConfirmation = true
                    } label: {
                        Text("Apply")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.mango)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppColor.mango.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }

            // Secondary metrics
            HStack(spacing: 16) {
                metricItem(label: "20m Avg", value: "\(Int(result.twentyMinuteAvgPower.rounded()))", unit: "W")
                metricItem(label: "Max", value: "\(result.maxPower)", unit: "W")
                metricItem(label: "95%", value: "\(result.estimatedFTP)", unit: "W")
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func metricItem(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.slash")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.15))
            Text("No FTP Tests Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text("Complete an FTP test to see your results here.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}
