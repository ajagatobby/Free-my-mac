//
//  StorageBar.swift
//  FreeUp
//
//  Compact storage bar — 4px strip with three segments (used/reclaimable/free)
//  and a one-line mono legend. Replaces the old card-style storage view.
//

import SwiftUI

struct StorageBar: View {
    let volumeInfo: VolumeInfo?
    let reclaimableSpace: Int64

    private var usedRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        let net = max(info.usedCapacity - reclaimableSpace, 0)
        return Double(net) / Double(info.totalCapacity)
    }

    private var reclaimableRatio: Double {
        guard let info = volumeInfo, info.totalCapacity > 0 else { return 0 }
        return Double(min(reclaimableSpace, info.usedCapacity)) / Double(info.totalCapacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 1) {
                    if usedRatio > 0 {
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(width: w * usedRatio)
                    }
                    if reclaimableRatio > 0 {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: w * reclaimableRatio)
                    }
                    Rectangle()
                        .fill(Color(.quaternaryLabelColor))
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())

            HStack(spacing: 14) {
                legendItem(color: .secondary, label: "Used",
                           value: volumeInfo.map { ByteFormatter.format(max($0.usedCapacity - reclaimableSpace, 0)) })
                if reclaimableSpace > 0 {
                    legendItem(color: .accentColor, label: "Reclaimable",
                               value: ByteFormatter.format(reclaimableSpace))
                }
                legendItem(color: Color(.quaternaryLabelColor), label: "Free",
                           value: volumeInfo?.formattedAvailable)
                Spacer()
            }
        }
    }

    private func legendItem(color: Color, label: String, value: String?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(FUFont.caption).foregroundStyle(.tertiary)
            if let value {
                Text(value).font(FUFont.monoCaption).foregroundStyle(.secondary)
            }
        }
    }
}
