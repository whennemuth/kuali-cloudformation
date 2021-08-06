package org.bu.jenkins.dao;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.dao.dockerhub.DockerhubCredentials;
import org.bu.jenkins.dao.dockerhub.DockerhubImages;
import org.bu.jenkins.dao.dockerhub.DockerhubRepositories;
import org.bu.jenkins.dao.dockerhub.DockerhubToken;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

public class DockerhubDAO extends AbstractDockerDAO {

	Logger logger = LogManager.getLogger(DockerhubDAO.class.getName());

	private DockerhubCredentials credentials;
	private Exception exception;
	
	public DockerhubDAO(DockerhubCredentials credentials) {
		this.credentials = credentials;
	}

	@Override
	public List<String> getImages() {

		DockerhubToken token = new DockerhubToken(credentials, true);
		String tokenStr = token.getValue();
		
		if(tokenStr == null && token.hasException()) {
			return Arrays.asList(new String[] {
				token.getException().getMessage()
			});
		}
		else {
			DockerhubRepositories repos = new DockerhubRepositories(credentials.getOrganization(), tokenStr);
			List<String> images = new ArrayList<String>();
			for(String repo : repos.getListing()) {
				if(repo.equalsIgnoreCase(credentials.getRepository())) {
					images.addAll(
						new DockerhubImages(
							credentials.getOrganization(),
							credentials.getRepository(), 
							tokenStr)
						.getListing());
				}
			}
			return images;
		}
	}

	public Exception getException() {
		return exception;
	}
	public boolean hasException() {
		return exception != null;
	}

	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		DockerhubDAO dao = new DockerhubDAO(new DockerhubCredentials()
				.setUserName(namedargs.get("username", "buistuser"))
				.setPassword(namedargs.get("password"))
				.setRepository(namedargs.get("repository", "research-pdf"))
				.setOrganization(namedargs.get("organization", "kuali")));

		List<String> images = dao.getImages();
		for(String image : images) {
			System.out.println(image);
		}
	}
}
