package edu.bu.ist.apps.aws.lambda;

import java.io.IOException;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Map;

import org.json.JSONObject;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.lambda.runtime.RequestHandler;

import edu.bu.ist.apps.aws.task.TaskFactory;
import edu.bu.ist.apps.aws.task.TaskRunner;

/**
 * Documentation for RequestHandler interface:
 * https://docs.aws.amazon.com/lambda/latest/dg/java-programming-model-handler-types.html
 * https://docs.aws.amazon.com/lambda/latest/dg/java-handler-using-predefined-interfaces.html
 * 
 * Example Implementation for java:
 * https://github.com/stelligent/cloudformation-custom-resources/blob/master/lambda/java/src/main/java/com/stelligent/customresource/CustomResourceHandler.java
 * 
 * @author wrh
 *
 */
public class CustomResourceHandler implements RequestHandler<Map<String, Object>, Object> {

	protected Context context;
	protected Map<String, Object> input;
	protected String responseStatus = "SUCCESS"; 
	protected LambdaLogger logger;
	
	@Override
	public Object handleRequest(Map<String, Object> input, Context context) {
		
		this.input = input;
		this.context = context;		
		this.logger = context.getLogger();

		/**
		 * NOTE: You must send a response with a status code on all cases if this request is being made by
		 * cloud-formation as part of a lambda-backed custom resource call. If no response is sent, 
		 * cloud-formation will hang for a long time before eventually responding with:
		 * "Custom Resource failed to stabilize in expected time" and rolling back.
		 * If this happens, rollback will hang and you will have trouble deleting the stack.
		 */
		try {
			sendResponse(input, context, getResponseData());
		}
		catch(Exception e) {
			responseStatus = "FAILED";
			// This should make it as a single entry in cloudwatch logs, not separate entry per line of stacktrace.
			e.printStackTrace(System.err);
			sendResponse(input, context, null);
		}
	    
	    return null;
	}
	
	ResponseData getResponseData() throws Exception {    
	    String requestType = String.valueOf(input.get("RequestType")).toUpperCase();
	    
	    ResponseDataParms parms = new ResponseDataParms()
	    		.setInput(input)
	    		.setRequestType(requestType)
	    		.setTaskFactory(new TaskFactory())
	    		.setTaskRunner(new TaskRunner())
	    		.setBase64(false)
	    		.setLogger((String msg) -> logger.log(msg));
	    
	    if(parms.isUnknownRequestType()) {
	    	logger.log("input.requestType: ERROR! Unknown requestType \"" + String.valueOf(requestType + "\""));
		    responseStatus = "FAILED";
	    }
	    else {
	    	logger.log("input.requestType: " + requestType);
	    }
	    
	    return new ResponseData(parms);	    	
	}

	void sendResponse(
			final Map<String, Object> input,
		    final Context context,
		    ResponseData responseData) {
				    
	    URL url;
	    try {
	    	String responseUrl = (String) input.get("ResponseURL");
	    	url = new URL(responseUrl);
	        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
	        connection.setDoOutput(true);
	        connection.setRequestMethod("PUT");
	    	
	        // Add the standard Custom Resource Request Object properties per reference:
	        // https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/crpg-ref-requests.html
	        JSONObject responseBody = new JSONObject();
	        responseBody.put("Status", responseStatus);
	        responseBody.put("PhysicalResourceId", context.getLogStreamName());
	        responseBody.put("StackId", input.get("StackId"));
	        responseBody.put("RequestId", input.get("RequestId"));
	        responseBody.put("LogicalResourceId", input.get("LogicalResourceId"));
	        if(responseData != null && ! responseData.isEmpty()) {
	        	responseBody.put("Data", new JSONObject(responseData));
	        }	        
	        
	        OutputStreamWriter response = new OutputStreamWriter(connection.getOutputStream());
	        response.write(responseBody.toString());
	        response.close();
	        context.getLogger().log("Response Code: " + connection.getResponseCode());
	    }
	    catch(IOException e) {
	    	context.getLogger().log(e.getMessage());
	    	e.printStackTrace(System.err);
	    }
	}

}
