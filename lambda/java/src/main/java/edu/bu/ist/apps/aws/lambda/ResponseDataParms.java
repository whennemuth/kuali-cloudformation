package edu.bu.ist.apps.aws.lambda;

import java.util.Comparator;
import java.util.Map;
import java.util.TreeMap;

import edu.bu.ist.apps.aws.task.TaskFactory;
import edu.bu.ist.apps.aws.task.TaskRunner;

public class ResponseDataParms {
	private TreeMap<String, Object> input = new TreeMap<String, Object>(new Comparator<String>() {
		@Override
		public int compare(String s1, String s2) {
			// Returns a negative integer, zero, or a positive integer as the first argument is less than, equal to, or greater than the second
			if("ResourceProperties".equalsIgnoreCase(s1) && "ResourceProperties".equalsIgnoreCase(s2)) {
				return 0;
			}
			else if("ResourceProperties".equalsIgnoreCase(s1)) {
				return 1;
			}
			else if("ResourceProperties".equalsIgnoreCase(s2)) {
				return -1;
			}
			else {
				return s1.compareTo(s2);
			}
		}		
	});
	private String message;
	private boolean base64;
	private Logger logger;
	private TaskFactory taskFactory;
	private TaskRunner taskRunner;
	public Map<String, Object> getInput() {
		return input;
	}
	public ResponseDataParms setInput(Map<String, Object> input) {
		if(input == null)
			return this;
		this.input.clear();
		this.input.putAll(input);
		return this;
	}
	public void addInput(String key, Object item) {
		input.put(key, item);
	}
	public String getMessage() {
		return message;
	}
	public ResponseDataParms setMessage(String message) {
		this.message = message;
		return this;
	}
	public boolean isBase64() {
		return base64;
	}
	public ResponseDataParms setBase64(boolean base64) {
		this.base64 = base64;
		return this;
	}
	public Logger getLogger() {
		return logger;
	}
	public ResponseDataParms setLogger(Logger logger) {
		this.logger = logger;
		return this;
	}
	public TaskFactory getTaskFactory() {
		return taskFactory;
	}
	public ResponseDataParms setTaskFactory(TaskFactory taskFactory) {
		this.taskFactory = taskFactory;
		return this;
	}
	public TaskRunner getTaskRunner() {
		return taskRunner;
	}
	public ResponseDataParms setTaskRunner(TaskRunner taskRunner) {
		this.taskRunner = taskRunner;
		return this;
	}
}
