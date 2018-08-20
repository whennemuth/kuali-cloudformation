package edu.bu.ist.apps.aws.lambda;

import java.util.LinkedHashMap;
import java.util.Map;

import org.json.JSONObject;

import edu.bu.ist.apps.aws.task.Task;
import edu.bu.ist.apps.aws.task.TaskFactory;
import edu.bu.ist.apps.aws.task.TaskResult;
import edu.bu.ist.apps.aws.task.TaskRunner;

/**
 * When calling a lambda function custom resource from a cloudformation stack template, any items beyond the service token that
 * are included its properties set are are passed as parameters into the lambda function and are available in the input map as
 * a nested map keyed as "ResourceProperties". This is according to cloudformation:
 * https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/crpg-ref-requests.html
 * <p>
 * This class extends the input map with convenience functions.
 * Included are logging statements to Logger, whose implemention should be logging to a com.amazonaws.services.lambda.runtime.LambdaLogger
 * so the response data will be shown in cloudwatch logs (minus the sensitive data).
 * @author wrh
 *
 */
public class ResponseData extends LinkedHashMap<String, Object> {

	private static final long serialVersionUID = 42155840541234301L;
	private ResponseDataParms parms;
	
	/**
	 * Restrict default constructor
	 */
	@SuppressWarnings("unused")
	private ResponseData() {
		super();
	}
	
	public ResponseData(ResponseDataParms parms) {
		this.parms = parms;
		
		try {	
			if(parms.isDeleteRequestType() ) {
				log("-----------------------------------------");
				log("   DELETING RESOURCE...");
				log("-----------------------------------------");
				log("Delete successful.");
			}
			else {
				parseInput();
			}
		}
		catch (Exception e) {
			e.printStackTrace(System.err);
			putAndLog("ERROR - " + e.getClass().getSimpleName() + ": ", e.getMessage());
		}
	}
	
	/**
	 * Strip out the task identifier from the ResourceProperties map and return another map
	 * resulting from running the corresponding task.
	 * @throws Exception 
	 */
	private void parseInput() throws Exception {
		
		// Put the original input back into the output for debugging purposes.
		log("-----------------------------------------");
		log("   INPUT:");
		log("-----------------------------------------");
		
		// ResourceProperties are intended as input parameters for a lambda function.
		// Run the lambda function with these parameters and put the results to this map.
		if(parms.getInput().containsKey("ResourceProperties")) {
			
			putAndLog("input", parms.getInput());
			
			Object rsrcProps = parms.getInput().get("ResourceProperties");
			Task task = parms.getTaskFactory().extractTask(rsrcProps, parms.getLogger());
			
			if(! Task.UNKNOWN.equals(task)) {
				
				TaskResult result = parms.getTaskRunner().run(task, rsrcProps, parms.getLogger());
				
				if(result.isValid()) {
					
					if(result.containsIllegalCharacters() || parms.isBase64()) {
						result.convertToBase64();
					}
					
					putAll(result.getMaskedResults());
					
					put("result", result.getMaskedResults());
					
					log("-----------------------------------------");
					log("   OUTPUT:");
					log("-----------------------------------------");
					log("result", result.getMaskedResultsForLogging(), null);
				}
				log(" ");
			}
		}
		else {
			parms.addInput("ResourceProperties", "ERROR! No Resource Properties!");
			putAndLog("input", parms.getInput());
			log(" ");
		}
	}
	
	private void putAndLog(Object key, Object val) {
		put(String.valueOf(key), val);
		log(key, val, null);
	}
	
	@SuppressWarnings("unused")
	private void putAndLog(Object key, Object val, String prefix) {
		put(String.valueOf(key), val);
		log(key, val, prefix);
	}
	
	/**
	 * Log an object as "key: object.toString()", unless object is a map. If a map, then recurse
	 * against the maps keySet until the entire original object is logged as a "flattened" item.
	 * 
	 * @param key1
	 * @param val
	 * @param prefix
	 */
	private void log(Object key1, Object val, String prefix) {
		if(val instanceof Map<?,?>) {
			Map<?,?> map = ((Map<?,?>) val);
			for(Object key2 : map.keySet()) {
				StringBuilder prfx = new StringBuilder();
				if(prefix != null && ! prefix.isEmpty()) {
					prfx.append(prefix).append(".");
				}
				prfx.append(String.valueOf(key1));
				log(key2, map.get(key2), prfx.toString());
			}
		}
		else {
			StringBuilder logstr = new StringBuilder(String.valueOf(key1));
			if(prefix != null && ! prefix.isEmpty()) {
				logstr.insert(0, ".").insert(0, prefix);
			}
			logstr.append(": ").append(String.valueOf(val));
			log(logstr.toString());
		}
	}
	
	private void log(String s) {
		parms.getLogger().log(s);
	}

	public boolean hasInput() {
		return ! "ERROR! NO INPUT!".equals(get("input"));
	}
	
	public boolean hasResourceProperties() {
		return ! "ERROR! No Resource Properties!".equals(get("input.ResourceProperties"));
		
	}
	
	public static void main(String[] args) throws Exception {

		Map<String, Object> resourceProperties = new LinkedHashMap<String, Object>();
		resourceProperties.put("task", Task.CONTAINER_ENV_VARS.getShortname());
		resourceProperties.put("region", "us-east-1");
		resourceProperties.put("s3bucket", "kuali-research-ec2-setup");
		resourceProperties.put("s3file", "qa/core/environment.variables.s3");
		resourceProperties.put("profile", "ecr.access");
		resourceProperties.put("outputmask", "{"
				+ "class: edu.bu.ist.apps.aws.task.BasicOutputMask, "
				+ "parameters: { "
				+ "  fieldsToMask: { "
				+ "    full: [], "
				+ "    logs: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MONGO_PASS, SERVICE_SECRET_1]"
				+ "  }"
				+ "}}");
		
		Map<String, Object> input = new LinkedHashMap<String, Object>();
		input.put("RequestType", "Create");
		input.put("ResourceProperties", resourceProperties);
		
		Logger logger = (String msg) -> { System.out.println(msg); };
		
		ResponseData response = new ResponseData(new ResponseDataParms()
	    		.setInput(input)
	    		.setTaskFactory(new TaskFactory())
	    		.setTaskRunner(new TaskRunner())
	    		.setBase64(false)
	    		.setLogger(logger));
		
		System.out.println(new JSONObject(response));
	}
}
