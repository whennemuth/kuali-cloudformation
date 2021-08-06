package org.bu.jenkins.dao.dockerhub;

import java.net.HttpURLConnection;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Get a listing of all repositories in a dockerhub account/organization
 * 
 * @author wrh
 *
 */
public class DockerhubRepositories extends AbstractDockerhubAPICall {
	
	Logger logger = LogManager.getLogger(DockerhubRepositories.class.getName());

	private String organization;
	private String token;
	private List<String> repositories = new ArrayList<String>();
	
	public DockerhubRepositories(String organization, String token) {
		this.organization = organization;
		this.token = token;
	}

	@Override
	public String getRequestMethod() {
		return "GET";
	}

	@Override
	public String getLink() {
		return String.format(
			"https://hub.docker.com/v2/repositories/%s/?page_size=10000",
			organization);
	}

	@Override
	public String getPostData() {
		return null; 
	}

	@Override
	public void processJsonResponse(String json) throws Exception {
		ObjectMapper objectMapper = new ObjectMapper();
		JsonNode jsonNode = objectMapper.readTree(json);
		// System.out.println(jsonNode.toPrettyString());	
		if(jsonNode.hasNonNull("results") && jsonNode.get("results").isArray()) {
			Iterator<JsonNode> iterator = jsonNode.get("results").elements(); 
			while(iterator.hasNext()) {
				JsonNode repo = (JsonNode) iterator.next();
				if(repo.hasNonNull("name")) {
					repositories.add(repo.get("name").asText());
				}				
			}
		}
	}

	@Override
	public void setCustomRequestProperties(HttpURLConnection connection) {
		connection.addRequestProperty("Authorization", "JWT " + token);
	}
	
	public List<String> getListing() {

		/**
		 * curl -s -H 
		 *   "Authorization: JWT ${TOKEN}" 
		 *   https://hub.docker.com/v2/repositories/${ORG}/?page_size=10000 
		 *   | jq -r '.results|.[]|.name'
		 */
		
		sendRequest();
		
		return repositories;
	}
	
	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		DockerhubCredentials credentials = new DockerhubCredentials()
			.setUserName(namedargs.get("username", "buistuser"))
			.setPassword(namedargs.get("password"))
			.setRepository(namedargs.get("repository", "research-pdf"))
			.setOrganization(namedargs.get("organization", "kuali"));
		
		DockerhubToken token = new DockerhubToken(credentials, true);

		DockerhubRepositories repos = new DockerhubRepositories(credentials.getOrganization(), token.getValue());
		
		for(String repo : repos.getListing()) {
			System.out.println(repo);
		}
	}
}
