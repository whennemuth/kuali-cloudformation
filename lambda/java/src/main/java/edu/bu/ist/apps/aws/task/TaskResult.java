package edu.bu.ist.apps.aws.task;

import java.util.LinkedHashMap;
import java.util.Map;

public class TaskResult {

	private LinkedHashMap<String, Object> results = new LinkedHashMap<String, Object>();
	
	/**
	 * Restrict default constructor
	 */
	@SuppressWarnings("unused")
	private TaskResult() {
		super();
	}
	
	public TaskResult(Map<String, Object> rawResult) {
		putAll(rawResult);
	}
	
	public void putAll(Map<String, Object> results) {
		if(results == null)
			return;
		results.putAll(results);
	}
	
	public void put(String key, Object value) {
		results.put(key, value);
	}
	
	public LinkedHashMap<String, Object> getResults() {
		return results;
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
}
