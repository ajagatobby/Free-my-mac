//
//  StorageBar.swift
//  FreeUp
//
//  Compact three-segment disk gauge with a one-line mono-numeric
//  readout. Used = neutral dark; reclaimable = orange (signals action,
//  not danger); free = light.
//

import SwiftUI

struct StorageBar: View {
    let volumeInfo: VolumeInfo?
    let reclaimableSpace: Int64

    private var usedBytes: Int64 {
        guard let info = volumeInfo else { return 0 }
        return max(info.usedCapacity - reclaimableSpace, 0)
    }

    private var usedRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(usedBytes) / Double(info.totalCapacity)
    }

    private var reclaimableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(min(reclaimableSpace, info.usedCapacity)) / Double(info.totalCapacity)
    }

    private var percentUsed: Int {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Int((Double(info.usedCapacity) / Double(info.totalCapacity)) * 100.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar
                .frame(height: 4)
                .clipShape(Capsule())

            HStack(spacing: 4) {
                Text("\(percentUsed)%")
                    .font(FUFont.monoSmall)
                    .foregroundStyle(.secondary)
                Text("used")
                    .font(FUFont.label)
                    .foregroundStyle(.tertiary)
                if reclaimableSpace > 0 {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Circle()
                        .fill(Color(nsColor: .systemOrange))
                        .frame(width: 5, height: 5)
                    Text(ByteFormatter.format(reclaimableSpace))
                        .font(FUFont.monoSmall)
                        .foregroundStyle(.secondary)
                    Text("reclaimable")
                        .font(FUFont.label)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .help(helpText)
    }

    private var bar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Base rail — the "free" region sits here.
                Capsule()
                    .fill(Color(.quaternaryLabelColor).opacity(0.6))

                // Used + reclaimable filled portion.
                HStack(spacing: 0) {
                    if usedRatio > 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.85))
                            .frame(width: w * usedRatio)
                    }
                    if reclaimableRatio > 0 {
                        Rectangle()
                            .fill(Color(nsColor: .systemOrange))
                            .frame(width: w * reclaimableRatio)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var helpText: String {
        guard let info = volumeInfo else { return "" }
        let usedStr = ByteFormatter.format(usedBytes)
        let reclaimStr = ByteFormatter.format(reclaimableSpace)
        let freeStr = ByteFormatter.format(info.availableCapacity)
        let totalStr = info.formattedTotal
        return "Used \(usedStr) · Reclaimable \(reclaimStr) · Free \(freeStr) of \(totalStr)"
    }
}
