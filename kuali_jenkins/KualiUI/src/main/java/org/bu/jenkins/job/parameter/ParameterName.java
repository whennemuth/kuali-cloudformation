package org.bu.jenkins.job.parameter;

import org.bu.jenkins.job.JobParameterMetadata;

/**
 * Enum for all legal values that the "parameter_name" querystring parameter can be set to.
 * Each enum value corresponds to a single field that renders dynamic content in a jenkins job.
 * 
 * @author wrh
 *
 */
public enum ParameterName implements JobParameterMetadata {
	ECR_URL("ECRUrl", "ecr-url"),
	ECR_IMAGES("ECRImages", "ecr-images"),
	DOCKER_IMAGES("DockerImages", "docker-images"),
	GIT_REFS("GitRefs", "git-refs"),
	GIT_COMMIT("GitCommit", "git-commit"),
	INVALID("InvalidState", "invalid-state");

	private String viewName;
	private String templateSelector;
	
	ParameterName(String viewName, String templateSelector) {
		this.viewName = viewName;
		this.templateSelector = templateSelector;
	}
	@Override
	public String getViewName() {
		return viewName;
	}
	@Override
	public String getTemplateSelector() {
		return templateSelector;
	}
	public static ParameterName tryValue(String val) {
		try {
			if(val == null || val.isBlank()) {
				return null;
			}
			return ParameterName.valueOf(val.toUpperCase());
		} 
		catch (IllegalArgumentException e) {
			return null;
		}
	}
}