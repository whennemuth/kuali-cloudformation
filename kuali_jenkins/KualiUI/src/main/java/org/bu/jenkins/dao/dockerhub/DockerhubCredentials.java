package org.bu.jenkins.dao.dockerhub;

public class DockerhubCredentials {
	
	private String userName;
	private String password;
	private String organization;
	private String repository;
	private Exception exception;

	public DockerhubCredentials() {
		super();
	}

	public String getUserName() {
		return userName;
	}

	public DockerhubCredentials setUserName(String userName) {
		this.userName = userName;
		return this;
	}

	public String getPassword() {
		return password;
	}

	public DockerhubCredentials setPassword(String password) {
		this.password = password;
		return this;
	}

	public String getOrganization() {
		return organization;
	}

	public DockerhubCredentials setOrganization(String organization) {
		this.organization = organization;
		return this;
	}

	public String getRepository() {
		return repository;
	}

	public DockerhubCredentials setRepository(String repository) {
		this.repository = repository;
		return this;
	}

	public Exception getException() {
		return exception;
	}

	public boolean hasException(Exception exception) {
		return this.exception != null;
	}

}
