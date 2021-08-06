package org.bu.jenkins.dao.dockerhub;

import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * This class performs all of the boilerplate actions involved in making an 
 * http request to the dockerhub api with credentials. Subclasses will provide the specific implementations 
 * for getting the credentials, target url, request type, and what to do with the response.
 *  
 * @author wrh
 *
 */
public abstract class AbstractDockerhubAPICall {

	Logger logger = LogManager.getLogger(AbstractDockerhubAPICall.class.getName());

	protected Exception exception;

	public abstract String getRequestMethod();
	
	public abstract String getLink();
	
	public abstract String getPostData();
	
	public abstract void processJsonResponse(String json) throws Exception;
	
	public abstract void setCustomRequestProperties(HttpURLConnection connection);
	
	protected void sendRequest() {
		HttpURLConnection connection = null;
		try {
			URL url = new URL(getLink());
			connection = (HttpURLConnection) url.openConnection();
			connection.setDoOutput(true);
			connection.setInstanceFollowRedirects(true);
			connection.setRequestMethod(getRequestMethod());
			connection.setUseCaches(false);
			
			connection.setRequestProperty("Content-Type", "application/json");
			connection.setRequestProperty("charset", "utf-8");
			connection.setRequestProperty("Accept", "application/json");
			
			setCustomRequestProperties(connection);
			
			if("POST".equalsIgnoreCase(getRequestMethod())) {				
		        try(DataOutputStream wr = new DataOutputStream(connection.getOutputStream())) {
			        wr.writeBytes(getPostData());	        	
		        }				
			}
	        
	        int responseCode = connection.getResponseCode();
	        if(responseCode == HttpURLConnection.HTTP_OK) {
	        	handleResponse(connection);
	        }
	        else {
	        	String msg = String.format(
	        		"responseCode: %s, responseMessage: %s",
	        		String.valueOf(responseCode),
	        		connection.getResponseMessage()
	        	);
	        	logger.error(msg);
	        	this.exception = new RuntimeException(msg);
	        }
		} 
		catch (Exception e) {
			logger.error(e.getMessage(), e);
			this.exception = e;
		}
		finally {
			if(connection != null) {
				connection.disconnect();
			}			
		}
	}

	private void handleResponse(HttpURLConnection connection) throws Exception {
		try(BufferedReader br = new BufferedReader(
			new InputStreamReader(connection.getInputStream(), "utf-8"))) {
			StringBuilder response = new StringBuilder();
			String responseLine = null;
			while ((responseLine = br.readLine()) != null) {
				response.append(responseLine.trim());
			}
			String json = response.toString();
			
			processJsonResponse(json);
		}		
	}

	public Exception getException() {
		return exception;
	}
	public boolean hasException() {
		return exception != null;
	}

}
