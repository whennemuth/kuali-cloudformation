package org.bu.jenkins.dao.dockerhub;

import java.net.HttpURLConnection;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Fetch the token issued by logging into dockerhub with a known user and credentials.
 * The token can be used in further api calls to dockerhub resources owned by the user.
 * 
 * @author wrh
 *
 */
public class DockerhubToken extends AbstractDockerhubAPICall {

	Logger logger = LogManager.getLogger(DockerhubToken.class.getName());

	private DockerhubCredentials credentials;
	private boolean cacheToken;
	private String token;
	
	public DockerhubToken(DockerhubCredentials credentials, boolean cacheToken) {
		this.credentials = credentials;
		this.cacheToken = cacheToken;
	}
	
	public String getValue() {
		/**
		 * curl -s -H 
		 *   "Content-Type: application/json" 
		 *   -X POST 
		 *   -d '{"username": "'${UNAME}'", "password": "'${UPASS}'"}' https://hub.docker.com/v2/users/login/ 
		 *   | jq -r .token
		 */
		if( ! cacheToken || token == null) {
			sendRequest();
		}
		return token;
	}

	@Override
	public String getRequestMethod() {
		return "POST";
	}

	@Override
	public String getLink() {
		return "https://hub.docker.com/v2/users/login/";
	}

	@Override
	public String getPostData() {
		return String.format(
			"{\"username\": \"%s\", \"password\": \"%s\"}",
			credentials.getUserName(),
			credentials.getPassword()
		);
	}

	@Override
	public void processJsonResponse(String json) throws Exception {
		ObjectMapper objectMapper = new ObjectMapper();
		JsonNode jsonNode = objectMapper.readTree(json);
		token = jsonNode.get("token").asText();
	}

	@Override
	public void setCustomRequestProperties(HttpURLConnection connection) {
		return;
	}
	
	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		DockerhubCredentials credentials = new DockerhubCredentials()
			.setUserName(namedargs.get("username", "buistuser"))
			.setPassword(namedargs.get("password"))
			.setRepository(namedargs.get("repository", "research-pdf"))
			.setOrganization(namedargs.get("organization", "kuali"));
		
		DockerhubToken token = new DockerhubToken(credentials, true);

		System.out.println(token.getValue());
	}

}
