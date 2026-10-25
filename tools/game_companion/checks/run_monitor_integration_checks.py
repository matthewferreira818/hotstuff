#!/usr/bin/env python3
"""Mac-only offline model/card checks; never builds or launches production engines.
Usage: python3 checks/run_monitor_integration_checks.py /path/to/temporary-output
"""
from pathlib import Path
import subprocess
import sys

source = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
room = (source / 'MeetingRoom.swift').read_text()
marker = '// A button on a crew member'
assert room.count(marker) == 1
fragment = room.split(marker)[0]
assert 'struct MeetingMonitorCard: View' in fragment
stubs = '''
enum DesignPreview { static let enabled = false }
enum Keychain {
 static func exists(_ service: String) -> Bool { false }
 static func read(_ service: String) -> Data? { nil }
 static func write(_ service: String,_ data: Data) -> Bool { false }
 static func remove(_ service: String) {}
}
'''
fixture = output / 'MeetingHubFixture.swift'
fixture.write_text(fragment + stubs)
executable = output / 'integration-checks'
command = ['xcrun', 'swiftc', '-parse-as-library'] + [str(source / name) for name in
    ['MeetingData.swift', 'MeetingMonitorData.swift', 'MeetingMonitor.swift']]
command += [str(fixture), str(source / 'checks/MeetingMonitorIntegrationChecks.swift'), '-o', str(executable)]
subprocess.run(command, check=True)
subprocess.run([str(executable), str(output)], check=True)
