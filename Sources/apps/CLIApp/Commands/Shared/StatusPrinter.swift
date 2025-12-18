import DeployCoreService

// MARK: - Status Helper

/// Print status in a formatted way
func printStatus(_ status: DeploymentStatus, mode: String) {
    let lambdaIcon = status.lambdaState == .running ? "✅" : "⏹️"
    let s3Icon = status.s3State == .running ? "✅" : "⏹️"
    let postgresIcon = status.postgresState == .running ? "✅" : "⏹️"
    let dynamodbIcon = status.dynamodbState == .running ? "✅" : "⏹️"

    print("")
    print("📊 Services Status (\(mode))")
    print("───────────────────────────────")
    print("\(lambdaIcon) Lambda:     \(status.lambdaState)")
    print("\(s3Icon) S3:         \(status.s3State)")
    print("\(postgresIcon) PostgreSQL: \(status.postgresState)")
    print("\(dynamodbIcon) DynamoDB:   \(status.dynamodbState)")
    print("")
}
