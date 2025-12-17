/// Type of local Docker service for development
public enum LocalServiceType: Sendable, Hashable {
    case database
    case s3
    case dynamodb
}
