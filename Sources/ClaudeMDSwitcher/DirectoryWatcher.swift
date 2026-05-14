import Foundation

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    func start(at url: URL, onChange: @escaping () -> Void) {
        stop()

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            FileHandle.standardError.write(Data("[ClaudeMDSwitcher] DirectoryWatcher: failed to open \(url.path)\n".utf8))
            return
        }
        self.fd = descriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler {
            onChange()
        }
        src.setCancelHandler { [fd = descriptor] in
            close(fd)
        }
        self.source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fd = -1
    }
}
