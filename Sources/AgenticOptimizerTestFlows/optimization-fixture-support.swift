import Agentic

func fixtureInferenceRealization<InferenceType: Inference>(
    _ inference: InferenceType.Type,
    identifier: String,
    configuration: InferenceRealizationConfiguration
) -> InferenceRealizationDefinition<InferenceType> {
    _ = inference

    return InferenceRealizationDefinition(
        identifier: InferenceRealizationIdentifier(
            rawValue: identifier
        ),
        configuration: configuration
    )
}
