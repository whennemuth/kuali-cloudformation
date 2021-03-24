package org.bu.jenkins.active_choices.dao;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

import org.bu.jenkins.active_choices.model.RdsInstance;

public class RdsDAOCache {

	private Map<String, RdsInstance> cache = new HashMap<String, RdsInstance>();	
	
	public boolean alreadyLoaded() {
		return cache.isEmpty() == false;
	}
	
	public RdsDAOCache add(RdsInstance instance) {
		RdsInstance cached = cache.get(instance.getArn());
		if(cached == null) {
			cache.put(instance.getArn(), instance);
		}
		else {
			if(cached.getSnapshots().size() < instance.getSnapshots().size()) {
				cached.setSnapshots(instance.getSnapshots());
			}
			if(cached.getTags().size() < instance.getTags().size()) {
				cached.setTags(instance.getTags());
			}
			cache.put(cached.getArn(), cached);
		}	
		
		return this;
	}

	public RdsDAOCache remove(RdsInstance instance) {
		cache.remove(instance.getArn());
		return this;
	}
	
	public void processAll(ProcessItem processor) {
		for(Entry<String, RdsInstance> entry : cache.entrySet()) {
			processor.process(entry.getValue());
		}
	}
	
	public RdsInstance getItem(TestItem tester) {
		for(Entry<String, RdsInstance> entry : cache.entrySet()) {
			if(tester.match(entry.getValue())) {
				return entry.getValue();
			}
		}
		return null;
	}
	
	public static interface ProcessItem {
		public void process(RdsInstance instance);
	}
	
	public static interface TestItem {
		public boolean match(RdsInstance instance);
	}

	public RdsInstance get(String rdsArn) {
		return cache.get(rdsArn);
	}

	public void put(String arn, RdsInstance instance) {
		cache.put(arn, instance);
	}
	
	public Collection<RdsInstance> getValues() {
		return cache.values();
	}
}
