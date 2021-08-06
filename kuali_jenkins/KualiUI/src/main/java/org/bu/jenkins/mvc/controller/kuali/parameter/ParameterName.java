package org.bu.jenkins.mvc.controller.kuali.parameter;

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
	ECR_IMAGES_CENTOS_JAVA_TOMCAT("ECRImagesCentosJavaTomcat", "ecr-images-centos-java-tomcat"),
	ECR_TAGS("ECRTags", "ecr-tags"),
	DOCKER_IMAGES("DockerImages", "docker-images"),
	DOCKERHUB_TOKEN("DockerhubToken", "dockerhub-token"),
	GIT_REFS("GitRefs", "git-refs"),
	GIT_COMMIT("GitCommit", "git-commit"),
	RELEASE_INFO("ReleaseInfo", "release-info"),
	RELEASE_INFO_PDF("ReleaseInfoPDF", "release-info-pdf"),
	KUALICO_PDF_IMAGES("KualicoPdfImages", "kualico-pdf-images"),
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