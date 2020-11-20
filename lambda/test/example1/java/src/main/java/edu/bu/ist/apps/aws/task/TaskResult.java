package edu.bu.ist.apps.aws.task;

import java.io.BufferedInputStream;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import edu.bu.ist.apps.aws.task.s3.S3File;
import edu.bu.ist.apps.aws.task.s3.S3FileParms;

/**
 * A TaskResult is an object that represents all output of a particular task.
 * For example if the lambda function were invoking this java application, it would be passing in a "task"
 * parameter to identify what function it is to perform. That function should return some result, as in the 
 * case of a lookup, or success code in the case of some void operation, etc.
 * 
 * @author wrh
 *
 */
public class TaskResult {

	private LinkedHashMap<String, Object> results = new LinkedHashMap<String, Object>();
	private OutputMask outputMask;
	
	/**
	 * Restrict default constructor
	 */
	private TaskResult() {
		super();
	}
	
	private TaskResult(OutputMask outputMask) {
		super();
		this.outputMask = outputMask;
	}
	
	
	public static TaskResult getInstanceFromMap(Map<String, Object> rawResult) {
		return getInstanceFromMap(rawResult, null);
	}	
	
	public static TaskResult getInstanceFromBlob(byte[] bytes) {
		return getInstanceFromBlob(bytes, null);
	}

	public static TaskResult getInstanceFromProperties(byte[] bytes) {
		return getInstanceFromProperties(bytes, null);
	}
	
	public static TaskResult getMergedInstance(List<TaskResult> results) {
		return getMergedInstance(results, null);
	}
	
	public static TaskResult getInstanceFromMap(Map<String, Object> rawResult, OutputMask outputMask) {
		TaskResult tr = new TaskResult(outputMask);
		tr.results.putAll(rawResult);
		return tr;
	}
	/**
	 * This method returns a TaskResult instance whose map contains a single entry keyed as "blob".
	 * The value of this entry is the provided byte array converted to a string (probably file content).
	 * @param bytes
	 * @param outputMask
	 * @return
	 */
	public static TaskResult getInstanceFromBlob(byte[] bytes, OutputMask outputMask) {
		TaskResult tr = new TaskResult(outputMask);
		tr.results.put("blob", new String(bytes));
		return tr;
	}

	/**
	 * This method returns a TaskResult instance whose map is loaded from a properties object.
	 * The properties object is loaded from the provided byte array converted to an input stream.
	 * @param bytes
	 * @return
	 */
	public static TaskResult getInstanceFromProperties(byte[] bytes, OutputMask outputMask) {
		
		TaskResult tr = new TaskResult(outputMask);
		BufferedInputStream bis = null;
		
		try {
			// Load the properties
			bis = new BufferedInputStream(new ByteArrayInputStream(bytes));
			Properties props = new Properties();
			props.load(bis);
			
			// Transfer the properties over to the map
			for(Object key : props.keySet()) {
				tr.results.put(String.valueOf(key), props.get(key));
			}
		} 
		catch (Exception e) {
			e.printStackTrace();
		}
		finally {
			if(bis != null) {
				try { bis.close(); } 
				catch (IOException e) { /* Do nothing */ }
			}
		}
		
		return tr;
	}
	
	public static TaskResult getMergedInstance(List<TaskResult> results, OutputMask outputmask) {
		TaskResult merged = new TaskResult(outputmask);
		for(TaskResult mergeable : results) {
			for(TaskResultItem item : mergeable.getResults()) {
				merged.put(item.getKey(), item.getUnmaskedValue());
			}
		}
		return merged;
	}
	
	public void putAll(Map<String, Object> results) {
		if(results == null)
			return;
		results.putAll(results);
	}
	
	public void put(String key, Object value) {
		results.put(key, value);
	}
	
	public void replaceKey(String existingKey, String newKey) {
		Object temp = results.get(existingKey);
		if(temp == null)
			return;
		results.put(newKey, temp);
		results.remove(existingKey);
	}
		
	public List<TaskResultItem> getResults() {
		List<TaskResultItem> maskedResults = new ArrayList<TaskResultItem>();

		for (Iterator<String> iterator = results.keySet().iterator(); iterator.hasNext();) {
			String key = iterator.next();
			Object value = results.get(key);
			maskedResults.add(new TaskResultItem(key, value, outputMask));
		}
		return maskedResults;
	}
	
	public Map<String, Object> getMaskedResults() {
		Map<String, Object> map = new LinkedHashMap<String, Object>();
		for(TaskResultItem result : getResults()) {
			map.put(result.getKey(), result.getValue());
		}
		return map;
	}
	
	public Map<String, Object> getMaskedResultsForLogging() {
		Map<String, Object> map = new LinkedHashMap<String, Object>();
		for(TaskResultItem result : getResults()) {
			map.put(result.getKey(), result.getLogValue());
		}
		return map;
	}
	
	public boolean containsIllegalCharacters() {
		return false;
		// TODO: Finish this.
	}
	public void convertToBase64() {
		// TODO: Finish this.
	}
	public boolean isValid() {
		return ! results.isEmpty();
	}

	@Override
	public String toString() {
		Map<String, Object> masked = getMaskedResultsForLogging();
		StringBuilder s = new StringBuilder("TaskResult [results=");
		for(String key : masked.keySet()) {
			s.append("\n   ").append(key).append("=").append(masked.get(key));
		}
		if(!masked.isEmpty())
			s.append("\n");
		s.append("]");
		return s.toString();
	}
	
	public static void main(String[] args) throws Exception {
		
		// Get a properties file from an S3 bucket
		S3File s3file = new S3File(new S3FileParms()
				.setRegion("us-east-1")
				.setBucketname("kuali-conf")
				.setFilename("qa/core/environment.variables.s3")
				.setProfilename("ecr.access")
				.setLogger((String msg) -> System.out.println(msg)));
		
		BasicOutputMask outputmask = new BasicOutputMask("{"
				+ "  fieldsToMask: { "
				+ "    full: [], "
				+ "    logs: [AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MONGO_PASS, SERVICE_SECRET_1]"
				+ "  }"
				+ "}");
		
		TaskResult tr = TaskResult.getInstanceFromProperties(s3file.getBytes(), outputmask);
		System.out.println(tr);
		
		
		// Get the raw content of the same file
		outputmask = new BasicOutputMask("{"
				+ "  fieldsToMask: { "
				+ "    full: [], "
				+ "    logs: [all]"
				+ "  }"
				+ "}");
		tr = TaskResult.getInstanceFromBlob(s3file.getBytes(), outputmask);
		System.out.println(tr);
	}
}
