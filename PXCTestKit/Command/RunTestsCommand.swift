//
//  RunTestsCommand.swift
//  pxctest
//
//  Created by Johannes Plunien on 23/11/16.
//  Copyright © 2016 Johannes Plunien. All rights reserved.
//

import FBSimulatorControl
import Foundation

final class RunTestsCommand {

    struct Configuration {
        let testRun: URL
        let deviceSet: URL
        let output: URL
        let simulators: [FBSimulatorConfiguration]
        let timeout: Double
    }

    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func run() throws {
        try XCTestBootstrapFrameworkLoader.loadPrivateFrameworks(nil)

        let testRun = try FBXCTestRun.withTestRunFile(atPath: configuration.testRun.path).build()
        let application = try FBApplicationDescriptor.application(withPath: testRun.testHostPath)

        // FIXME: Redirect logs to file, not /dev/null.
        let logger = FBControlCoreLogger.aslLoggerWriting(toFileDescriptor: FileHandle.nullDevice.fileDescriptor, withDebugLogging: false)
        let simulatorControlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: configuration.deviceSet.path, options: [])
        let control = try FBSimulatorControl.withConfiguration(simulatorControlConfiguration, logger: logger)

        let simulators = try configuration.simulators.map {
            try control.pool.allocateSimulator(with: $0, options: [.create, .reuse])
        }

        for simulator in simulators {
            if simulator.state == .booted {
                continue
            }
            try simulator.interact
                .bootSimulator()
                .perform()
        }

        let applicationLaunchConfiguration = FBApplicationLaunchConfiguration(
            application: application,
            arguments: testRun.arguments,
            environment: testRun.environment,
            options: []
        )

        let testLaunchConfiguration = FBTestLaunchConfiguration(testBundlePath: testRun.testBundlePath)
            .withApplicationLaunchConfiguration(applicationLaunchConfiguration)
            .withTimeout(configuration.timeout)
            .withTestsToSkip(testRun.testsToSkip)
            .withTestsToRun(testRun.testsToRun)

        var standardOutputReporters = [StandardOutputReporter]()

        for simulator in simulators {
            let reporter = StandardOutputReporter(simulatorIdentifier: "\(simulator.deviceConfiguration.deviceName) (\(simulator.osConfiguration.name))")
            standardOutputReporters.append(reporter)
            try simulator.interact
                .installApplication(application)
                .startTest(with: testLaunchConfiguration, reporter: reporter)
                .perform()
        }

        for simulator in simulators {
            try simulator.interact
                .waitUntilAllTestRunnersHaveFinishedTesting(withTimeout: configuration.timeout)
                .perform()
        }

        StandardOutputReporter.writeSummary(reporters: standardOutputReporters)
    }

}
