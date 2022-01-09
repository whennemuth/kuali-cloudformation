package org.bu.jenkins.mvc.controller.parameter.kuali;

import java.io.File;

import org.bu.jenkins.dao.AbstractGitDAO;
import org.bu.jenkins.job.JobParameterConfiguration;
import org.bu.jenkins.util.Argument;

public class GitQueryArguments {
	
	// The directory ssh keys would be found in if running in a docker container run from the image built for this application.
	public static final String JENKINS_SSH_KEY_DIR = "/root/.ssh";

	private JobParameterConfiguration config;
	private String sshKeyPath;

	public GitQueryArguments(JobParameterConfiguration config) {
		this.config = config;
	}

	public JobParameterConfiguration getConfig() {
		return config;
	}

	public String getRefType() {
		String reftype = config.getParameterMap().get(QueryStringParms.GIT_REF_TYPE.arg());
		if( ! Argument.isMissing(reftype)) {
			if(AbstractGitDAO.RefType.validRefType(reftype)) {
				return config.getParameterMap().get(QueryStringParms.GIT_REF_TYPE.arg());
			}
		}
		return null;
	}

	public String getRefValue() {
		return config.getParameterMap().get(QueryStringParms.GIT_REF.arg());
	}

	public String getRemoteUrl() {
		return config.getParameterMap().get(QueryStringParms.GIT_REMOTE_URL.arg());
	}

	public String getUsername() {
		return config.getParameterMap().get(QueryStringParms.GIT_USERNAME.arg());
	}

	public String getPersonalAccessToken() {
		return config.getParameterMap().get(QueryStringParms.GIT_PERSONAL_ACCESS_TOKEN.arg());
	}
	
	public boolean cannotUseToken() {
		if(Argument.isMissing(getUsername())) return true;
		if(Argument.isMissing(getPersonalAccessToken())) return true;
		return false;
	}
	
	public String getMissingRefTypeMessage() {
		return String.format(
				"The request was missing or contains an invalid entry for a required parameter: \"%s\"", 
				QueryStringParms.GIT_REF_TYPE.arg());
	}
	
	public String getInsufficientCredentialsMessage() {
		return String.format(
				"The request had one or more required parameters missing or invalid: %s, %s, %s",
				QueryStringParms.GIT_USERNAME.arg() + ": " + (Argument.isMissing(getUsername()) ? "missing" : getUsername()),
				QueryStringParms.GIT_PERSONAL_ACCESS_TOKEN.arg() + ": " + (Argument.isMissing(getPersonalAccessToken()) ? "missing" : "*******"),
				QueryStringParms.GIT_SSH_KEY.arg() + ": " + (Argument.isMissing(getSshKeyPath()) ? "missing" : getSshKeyPath()));
	}
	
	public String getMissingGitRemoteUrlMessage() {
		return String.format(
				"The request was missing a required parameter: \"%s\"", 
				QueryStringParms.GIT_REMOTE_URL.arg());
	}

	/**
	 * Get the true ssh key pathname indicated by the corresponding JobParameterConfiguration object property.
	 * 
	 * @param config
	 * @return
	 */
	public String getSshKeyPath() {
		if(sshKeyPath != null) {
			return sshKeyPath;
		}
		sshKeyPath = checkSshKey(config.getParameterMap().get(QueryStringParms.GIT_SSH_KEY.arg()));
		return sshKeyPath;
	}
	
	/**
	 * Given an sshKey file identifier, locate it in the file system  If it is a full file path (contains path separators) 
	 * check if the file actually exists and return null if it does not. If it is only a file name, try a few typical paths where the key 
	 * would be found. If after that, no ssh key file can yet be found, return null.
	 * @param config
	 * @return
	 */
	private String checkSshKey(String sshKeyPath) {
		if(Argument.isMissing(sshKeyPath)) {
			return null;
		}
		if(new File(sshKeyPath).isFile()) {
			return sshKeyPath;
		}
		if(sshKeyPath.contains(File.separator)) {
			return null;
		}
		
		String keyname = sshKeyPath;
		if(new File(JENKINS_SSH_KEY_DIR + keyname).isFile()) {
			return JENKINS_SSH_KEY_DIR + keyname;
		}
		sshKeyPath = System.getProperty("user.home") + File.separator + ".ssh" + File.separator + keyname;
		if(new File(sshKeyPath).isFile()) {
			return sshKeyPath;
		}
		return null;
	}
}
