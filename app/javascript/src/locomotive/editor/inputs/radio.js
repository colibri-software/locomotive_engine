import React, { Component } from 'react';

const RadioInput = ({ setting, getValue, getLabel, getLocalizedOptionLabel, handleChange, uiLocale }) => (
  <div className="editor-input editor-input-radio">
    <label className="editor-input--label">
      {getLabel(setting.label)}
    </label>
    <div className="editor-input--radio">
      {setting.options.map((option, index) =>
        <div className="editor-input-radio--option" key={`radio-${index}`}>
          <input
            type="radio"
            id={option.value}
            onChange={e => handleChange(e.target.id)}
            checked={getValue(null) === option.value}
          />
          {getLabel(option.label)}
        </div>
      )}
    </div>
  </div>
)

export default RadioInput;
