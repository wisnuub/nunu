import AppKit

// Launched from Finder/Dock there's no terminal, so keep a log file instead.
if isatty(STDERR_FILENO) == 0 {
    Paths.ensure(Paths.logs)
    freopen(Paths.logs.appendingPathComponent("nunu.log").path, "a", stderr)
    setvbuf(stderr, nil, _IOLBF, 0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)

    // SIGTERM/SIGINT (logout, `kill`, Ctrl-C) take the normal quit path so
    // Android still gets to save its state.
    let signals = [SIGTERM, SIGINT].map { sig -> DispatchSourceSignal in
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        // Hop off the main dispatch queue first: terminate() spins a nested run
        // loop waiting for the engine to stop, and main-queue work (the stop
        // task) can't run while we're still inside a main-queue block.
        source.setEventHandler {
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
        source.resume()
        return source
    }
    withExtendedLifetime((delegate, signals)) { app.run() }
}
