import Darwin
import Foundation

struct ListedEntry {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var allocSize: Int64
    var logicalSize: Int64
}

struct ListedDirectory {
    var entries: [ListedEntry]
    var directoryAlloc: Int64
    var unreadable: Bool
    var crossesVolume: Bool
}

/// Enumerates one directory with `getattrlistbulk`, the fastest metadata API on macOS.
enum DirectoryListing {
    private static let nameBit = attrgroup_t(UInt32(ATTR_CMN_NAME))
    private static let typeBit = attrgroup_t(UInt32(ATTR_CMN_OBJTYPE))
    private static let errorBit = attrgroup_t(UInt32(ATTR_CMN_ERROR))
    private static let allocBit = attrgroup_t(UInt32(ATTR_FILE_ALLOCSIZE))
    private static let logicalBit = attrgroup_t(UInt32(ATTR_FILE_DATALENGTH))
    private static let vDirectory: UInt32 = 2
    private static let vSymlink: UInt32 = 5
    private static let listOptions: UInt64 = 1

    static func list(_ path: String, rootDevice: dev_t) -> ListedDirectory {
        let fd = path.withCString { open($0, O_RDONLY) }
        if fd < 0 {
            return ListedDirectory(entries: [], directoryAlloc: 0, unreadable: true, crossesVolume: false)
        }
        defer { close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else {
            return ListedDirectory(entries: [], directoryAlloc: 0, unreadable: true, crossesVolume: false)
        }
        if info.st_dev != rootDevice {
            return ListedDirectory(entries: [], directoryAlloc: 0, unreadable: false, crossesVolume: true)
        }
        let directoryAlloc = Int64(info.st_blocks) * 512

        var query = attrlist()
        query.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        query.commonattr = attrgroup_t(
            UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_ERROR)
        )
        query.fileattr = attrgroup_t(UInt32(ATTR_FILE_ALLOCSIZE) | UInt32(ATTR_FILE_DATALENGTH))

        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        var entries: [ListedEntry] = []
        entries.reserveCapacity(64)

        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return getattrlistbulk(fd, &query, base, raw.count, listOptions)
            }
            if count < 0 {
                return ListedDirectory(entries: entries, directoryAlloc: directoryAlloc, unreadable: true, crossesVolume: false)
            }
            if count == 0 { break }

            buffer.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                for _ in 0..<count {
                    let length = Int(base.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                    if length < 8 || offset + length > raw.count { break }
                    if let entry = parse(base: base, offset: offset, length: length) {
                        entries.append(entry)
                    }
                    offset += length
                }
            }
        }

        return ListedDirectory(entries: entries, directoryAlloc: directoryAlloc, unreadable: false, crossesVolume: false)
    }

    private static func parse(base: UnsafeRawPointer, offset: Int, length: Int) -> ListedEntry? {
        let end = offset + length
        var cursor = offset + 4
        guard cursor + MemoryLayout<attribute_set_t>.size <= end else { return nil }
        let returned = base.loadUnaligned(fromByteOffset: cursor, as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size

        var name = ""
        if returned.commonattr & nameBit != 0 {
            guard cursor + MemoryLayout<attrreference_t>.size <= end else { return nil }
            let ref = base.loadUnaligned(fromByteOffset: cursor, as: attrreference_t.self)
            let nameAt = cursor + Int(ref.attr_dataoffset)
            if nameAt >= offset, nameAt < end {
                name = String(cString: base.advanced(by: nameAt).assumingMemoryBound(to: CChar.self))
            }
            cursor += MemoryLayout<attrreference_t>.size
        }
        if name.isEmpty || name == "." || name == ".." { return nil }

        var objType: UInt32 = 0
        if returned.commonattr & typeBit != 0 {
            guard cursor + 4 <= end else { return nil }
            objType = base.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
            cursor += 4
        }
        if returned.commonattr & errorBit != 0 {
            guard cursor + 4 <= end else { return nil }
            let error = base.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
            cursor += 4
            if error != 0 { return nil }
        }

        var alloc: Int64 = 0
        var logical: Int64 = 0
        if returned.fileattr & allocBit != 0 {
            guard cursor + 8 <= end else { return nil }
            alloc = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
            cursor += 8
        }
        if returned.fileattr & logicalBit != 0 {
            guard cursor + 8 <= end else { return nil }
            logical = base.loadUnaligned(fromByteOffset: cursor, as: Int64.self)
        }
        if alloc < 0 { alloc = 0 }
        if logical < 0 { logical = 0 }

        return ListedEntry(
            name: name,
            isDirectory: objType == vDirectory,
            isSymlink: objType == vSymlink,
            allocSize: alloc,
            logicalSize: logical
        )
    }
}
