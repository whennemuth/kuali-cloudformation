package edu.bu.ist.apps.aws.task;

public class TaskResultItem {

	private String key;
	private Object value;
	private OutputMask outputmask;
	
	public TaskResultItem(String key, Object value) {
		this(key, value, null);
	}
		
	public TaskResultItem(String key, Object value, OutputMask outputmask) {
		super();
		this.key = key;
		this.value = value;
		if(outputmask == null) {
			/**
			 * Don't mask anything - simply return the input value as the output value.
			 */
			this.outputmask = new OutputMask() {
				@Override public String getLogOutput(String key, Object value) { return String.valueOf(value); }
				@Override public String getOutput(String key, Object value) { return String.valueOf(value); }			
			};
		}
		else {
			this.outputmask = outputmask;
		}
	}
	
	public String getKey() {
		return key;
	}
	
	public String getLogValue() {
		return outputmask.getLogOutput(key, value);
	}
	
	public String getValue() {
		return outputmask.getOutput(key, value);
	}
	
	public Object getUnmaskedValue() {
		return value;
	}

	@Override
	public int hashCode() {
		final int prime = 31;
		int result = 1;
		result = prime * result + ((key == null) ? 0 : key.hashCode());
		return result;
	}

	@Override
	public boolean equals(Object obj) {
		if (this == obj)
			return true;
		if (obj == null)
			return false;
		if (getClass() != obj.getClass())
			return false;
		TaskResultItem other = (TaskResultItem) obj;
		if (key == null) {
			if (other.key != null)
				return false;
		} else if (!key.equals(other.key))
			return false;
		return true;
	}

}
