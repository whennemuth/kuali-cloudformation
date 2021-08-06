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

public class DockerhubImages extends AbstractDockerhubAPICall {
	
	Logger logger = LogManager.getLogger(DockerhubImages.class.getName());

	private String organization;
	private String repository;
	private String token;
	private List<String> images = new ArrayList<String>();
	
	public DockerhubImages(String organization, String repository, String token) {
		this.organization = organization;
		this.repository = repository;
		this.token = token;
	}

	@Override
	public String getRequestMethod() {
		return "GET";
	}

	@Override
	public String getLink() {
		return String.format(
			"https://hub.docker.com/v2/repositories/%s/%s/tags/?page_size=10000", 
			organization, 
			repository);
	}

	@Override
	public String getPostData() {
		return null;
	}

	@Override
	public void processJsonResponse(String json) throws Exception {
		ObjectMapper objectMapper = new ObjectMapper();
		JsonNode jsonNode = objectMapper.readTree(json);
		if(jsonNode.hasNonNull("results") && jsonNode.get("results").isArray()) {
			Iterator<JsonNode> iterator = jsonNode.get("results").elements(); 
			while(iterator.hasNext()) {
				JsonNode tag = (JsonNode) iterator.next();
				if(tag.hasNonNull("name")) {
					images.add(String.format(
							"%s/%s:%s", 
							organization,
							repository,
							tag.get("name").asText()));
				}
			}
		}
		if(images.isEmpty()) {
			images.add(String.format(
					"%s/%s:%s", 
					organization,
					repository,
					"latest"));
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
		 *   https://hub.docker.com/v2/repositories/${ORG}/${REPOSITORY}/tags/?page_size=10000 
		 *   | jq -r '.results|.[]|.name'
		 */
		sendRequest();
		
		return images;
	}
		
	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		DockerhubCredentials credentials = new DockerhubCredentials()
			.setUserName(namedargs.get("username", "buistuser"))
			.setPassword(namedargs.get("password"))
			.setRepository(namedargs.get("repository", "research-pdf"))
			.setOrganization(namedargs.get("organization", "kuali"));
		
		DockerhubToken token = new DockerhubToken(credentials, true);

		DockerhubImages images = new DockerhubImages(
				credentials.getOrganization(), 
				credentials.getRepository(),
				token.getValue());
		
		for(String image : images.getListing()) {
			System.out.println(image);
		}
	}	
}