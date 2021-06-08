package edu.bu.ist.apps.aws.lambda;

import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;

/**
 * This class is like the one it extends from, only it implements a 10 second timer for resource creation.
 * TODO: Not sure what this accomplishes, so need to look at notes in github for the link below to explain.
 * 
 * See similar:
 * https://github.com/stelligent/cloudformation-custom-resources/blob/master/lambda/java/src/main/java/com/stelligent/customresource/CustomResourceHandler.java
 * @author wrh
 *
 */
public class CustomResourceHandlerTimeout extends CustomResourceHandler implements RequestHandler<Map<String, Object>, Object> {

	@Override
	public Object handleRequest(Map<String, Object> input, Context context) {
		
		this.input = input;
		this.context = context;		
		this.logger = context.getLogger();
	    
	    ExecutorService service = Executors.newSingleThreadExecutor();
	    
	    String requestType = String.valueOf(input.get("RequestType")).toUpperCase();
	    logger.log("input.requestType: " + requestType);
	    try {
	    	if(requestType == null) {
	            throw new RuntimeException("RequestType is null!");
	        }

			Runnable r = new Runnable() {
				@Override
				public void run() {
					try {
						Thread.sleep(10000);
					}
					catch(final InterruptedException e) {
						// Do nothing.
					}
					
					try {
						sendResponse(input, context, getResponseData());
					}
					catch(Exception e) {
						// This should make it as a single entry in cloudwatch logs, not separate entry per line of stacktrace.
						throw new RuntimeException(e);
					}
				}
			};
			
		    Future<?> f = service.submit(r);
		    f.get(context.getRemainingTimeInMillis() - 1000, TimeUnit.MILLISECONDS);
	    }
	    catch(final TimeoutException | InterruptedException | ExecutionException e) {
	    	this.responseStatus = "FAILURE";
	    	sendResponse(input, context, null);
	    }
	    finally {
	    	service.shutdown();
	    }
	    
	    return null;
	}
}
