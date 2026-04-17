//
//  StorageBar.swift
//  FreeUp
//
//  Compact 4px three-segment strip — used/reclaimable/free.
//  No inline legend; the numeric readout is rendered by the caller so
//  narrow sidebars don't force abbreviation-hell truncation.
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
        .help(helpText)
    }

    private var helpText: String {
        guard let info = volumeInfo else { return "" }
        let used = max(info.usedCapacity - reclaimableSpace, 0)
        let usedStr = ByteFormatter.format(used)
        let reclaimStr = ByteFormatter.format(reclaimableSpace)
        let freeStr = ByteFormatter.format(info.availableCapacity)
        return "Used \(usedStr) · Reclaimable \(reclaimStr) · Free \(freeStr)"
    }
}
