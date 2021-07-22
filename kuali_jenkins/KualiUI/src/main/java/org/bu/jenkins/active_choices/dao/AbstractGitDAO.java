package org.bu.jenkins.active_choices.dao;

import java.util.List;

/**
 * Base class for implementing various methods for acquiring git output/info.
 * 
 * @author wrh
 *
 */
public abstract class AbstractGitDAO {

	public static enum RefType {
		BRANCH("heads"), TAG("tags");
		private String category;
		private RefType(String category) {
			this.category = category;
		}
		public static RefType get(String reftype) {
			for(RefType rt : RefType.values()) {
				if(rt.name().equalsIgnoreCase(reftype)) {
					return rt;
				}
			}
			return null;
		}
		public static boolean validRefType(String reftype) {
			return get(reftype) != null;
		}
		public String category() {
			return category;
		}
		public String categorySwitch() {
			return category.substring(0, 1);
		}
	}
	
	protected RefType refType;
	
	public AbstractGitDAO() {
		super();
	}

	public abstract List<String> getOutputList();

	public RefType getRefType() {
		return refType;
	}

	public AbstractGitDAO setRefType(RefType refType) {
		this.refType = refType;
		return this;
	}
}
