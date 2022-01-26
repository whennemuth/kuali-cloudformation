package org.bu.jenkins.mvc.controller.parameter.kuali;

/**
 * Enum for possible querystring arguments made in an http request for getting a parameter rendering or value
 * 
 * @author wrh
 *
 */
public enum QueryStringParms {
	PARAMETER_NAME,
	LANDSCAPE,
	HTML,
	SELECTED_ITEM,
	DOCKER_REPOSITORY_NAME,
	KUALICO_DOCKER_ORGANIZATION,
	KUALICO_DOCKER_REPOSITORY_NAME,
	KUALICO_DOCKER_USERNAME,
	KUALICO_DOCKER_PASSWORD,
	KUALICO_DOCKER_IMAGE_UPDATE,
	DOCKERHUB_TOKEN,
	DOCKER_TAG,
	GIT_REF,
	GIT_REF_TYPE,
	GIT_REMOTE_URL,
	GIT_USERNAME,
	GIT_PERSONAL_ACCESS_TOKEN,
	GIT_SSH_KEY,
	RENDER_NAME,
	RENDER_DESCRIPTION,
	BUILD_TYPE;
	public String arg() {
		return this.name().replaceAll("_", "-").toLowerCase();
	}
	public static String[] asArgArray() {
		String[] args = new String[QueryStringParms.values().length];
		for(int i=0; i<QueryStringParms.values().length; i++) {
			args[i] = QueryStringParms.values()[i].arg();
		}
		return args;
	}
}